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

# Download change-mate.md only if it doesn't already exist
if [ -f "change-mate.md" ]; then
  echo -e "${YELLOW}~${NC} change-mate.md already exists, skipping"
else
  curl -fsSL "$REPO_URL/change-mate.md" -o change-mate.md
  echo -e "${GREEN}✓${NC} created change-mate.md"
fi

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

echo ""
echo -e "${GREEN}change-mate is ready.${NC}"
echo ""
echo "next steps:"
echo "  1. start a claude code session in this project"
echo "  2. ask: 'what are we working on?'"
echo ""
