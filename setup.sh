#!/bin/bash

set -e

REPO_URL="https://raw.githubusercontent.com/allavallc/change-mate/main"
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo ""
echo "setting up change-mate..."
echo ""

# Download CHANGEMATE.md
curl -fsSL "$REPO_URL/CHANGEMATE.md" -o CHANGEMATE.md
echo -e "${GREEN}✓${NC} downloaded CHANGEMATE.md"

# Create folder structure
mkdir -p change-mate/backlog
mkdir -p change-mate/in-progress
mkdir -p change-mate/done
mkdir -p change-mate/blocked

# Add .gitkeep files so empty folders are tracked by git
touch change-mate/backlog/.gitkeep
touch change-mate/in-progress/.gitkeep
touch change-mate/done/.gitkeep
touch change-mate/blocked/.gitkeep

echo -e "${GREEN}✓${NC} created change-mate/ folder structure"

# Append import to CLAUDE.md if not already there
IMPORT_LINE="@CHANGEMATE.md"

if [ -f "CLAUDE.md" ]; then
  if grep -qF "$IMPORT_LINE" CLAUDE.md; then
    echo -e "${YELLOW}~${NC} CLAUDE.md already imports CHANGEMATE.md, skipping"
  else
    echo "" >> CLAUDE.md
    echo "# change-mate" >> CLAUDE.md
    echo "$IMPORT_LINE" >> CLAUDE.md
    echo -e "${GREEN}✓${NC} added change-mate import to existing CLAUDE.md"
  fi
else
  cat > CLAUDE.md << EOF
# change-mate
$IMPORT_LINE
EOF
  echo -e "${GREEN}✓${NC} created CLAUDE.md"
fi

# Check .gitignore — change-mate/ must not be ignored
if [ -f ".gitignore" ]; then
  if grep -qE "^change-mate" .gitignore; then
    echo ""
    echo -e "⚠️  WARNING: change-mate/ is in your .gitignore"
    echo "   Tickets won't sync between teammates until you remove it."
    echo "   Remove this line from .gitignore: change-mate"
    echo ""
  fi
fi

echo ""
echo -e "${GREEN}change-mate is ready.${NC}"
echo ""
echo "next steps:"
echo "  1. commit and push the change-mate/ folder to your repo"
echo "  2. have your team pull"
echo "  3. start a claude code session and ask: 'what are we working on?'"
echo ""
