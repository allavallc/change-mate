#!/bin/bash

set -e

REPO_URL="https://raw.githubusercontent.com/allavallc/change-mate/main"
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo ""
echo "setting up change-mate..."
echo ""

# Create folder structure first so we can drop files into it
mkdir -p change-mate/backlog
mkdir -p change-mate/in-progress
mkdir -p change-mate/done
mkdir -p change-mate/blocked
mkdir -p change-mate/not-doing

# Add .gitkeep files so empty folders are tracked by git
touch change-mate/backlog/.gitkeep
touch change-mate/in-progress/.gitkeep
touch change-mate/done/.gitkeep
touch change-mate/blocked/.gitkeep
touch change-mate/not-doing/.gitkeep

echo -e "${GREEN}✓${NC} created change-mate/ folder structure"

# Migrate legacy layout (root-level files) into change-mate/ if detected.
# Idempotent — only runs when legacy files are actually present.
LEGACY=0
for f in CHANGEMATE.md build.sh build_lib.py change-mate-board.html change-mate-config.json; do
  [ -f "$f" ] && LEGACY=1 && break
done

if [ $LEGACY -eq 1 ]; then
  echo ""
  echo -e "${YELLOW}legacy layout detected${NC} — these files live at repo root and should move into change-mate/:"
  for f in CHANGEMATE.md build.sh build_lib.py change-mate-board.html change-mate-config.json; do
    [ -f "$f" ] && echo "  • $f"
  done
  echo ""
  read -r -p "migrate now? [y/N] " REPLY
  if [ "$REPLY" = "y" ] || [ "$REPLY" = "Y" ]; then
    [ -f CHANGEMATE.md ]            && mv CHANGEMATE.md change-mate/CHANGEMATE.md            && echo -e "${GREEN}✓${NC} moved CHANGEMATE.md → change-mate/CHANGEMATE.md"
    [ -f build.sh ]                 && mv build.sh change-mate/build.sh                      && echo -e "${GREEN}✓${NC} moved build.sh → change-mate/build.sh"
    [ -f build_lib.py ]             && mv build_lib.py change-mate/build_lib.py              && echo -e "${GREEN}✓${NC} moved build_lib.py → change-mate/build_lib.py"
    [ -f change-mate-board.html ]   && mv change-mate-board.html change-mate/board.html      && echo -e "${GREEN}✓${NC} moved change-mate-board.html → change-mate/board.html"
    [ -f change-mate-config.json ]  && mv change-mate-config.json change-mate/config.json    && echo -e "${GREEN}✓${NC} moved change-mate-config.json → change-mate/config.json"
    if [ -f CLAUDE.md ] && grep -qF "@CHANGEMATE.md" CLAUDE.md && ! grep -qF "@change-mate/CHANGEMATE.md" CLAUDE.md; then
      sed -i.bak 's|@CHANGEMATE\.md|@change-mate/CHANGEMATE.md|g' CLAUDE.md && rm -f CLAUDE.md.bak
      echo -e "${GREEN}✓${NC} updated CLAUDE.md import to @change-mate/CHANGEMATE.md"
    fi
    echo -e "${GREEN}migration complete.${NC} commit the moves with git."
  else
    echo "skipped migration — nothing changed."
  fi
  echo ""
fi

# Download CHANGEMATE.md into change-mate/ if we don't have one yet
if [ ! -f "change-mate/CHANGEMATE.md" ]; then
  curl -fsSL "$REPO_URL/change-mate/CHANGEMATE.md" -o change-mate/CHANGEMATE.md
  echo -e "${GREEN}✓${NC} downloaded change-mate/CHANGEMATE.md"
else
  echo -e "${YELLOW}~${NC} change-mate/CHANGEMATE.md already present, skipping download"
fi

# Install product-manager skill into ~/.claude/skills/
SKILL_DIR="$HOME/.claude/skills/product-manager"
SKILL_FILE="$SKILL_DIR/SKILL.md"

mkdir -p "$SKILL_DIR"

if [ -f "$SKILL_FILE" ]; then
  echo -e "${YELLOW}~${NC} product-manager skill already installed at $SKILL_FILE"
  echo "   delete it and re-run setup if you want the latest version"
else
  curl -fsSL "$REPO_URL/skills/product-manager/SKILL.md" -o "$SKILL_FILE"
  echo -e "${GREEN}✓${NC} installed product-manager skill to $SKILL_FILE"
fi

# Append import to CLAUDE.md if not already there
IMPORT_LINE="@change-mate/CHANGEMATE.md"

if [ -f "CLAUDE.md" ]; then
  if grep -qF "$IMPORT_LINE" CLAUDE.md; then
    echo -e "${YELLOW}~${NC} CLAUDE.md already imports change-mate/CHANGEMATE.md, skipping"
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
echo "  3. start an agent session and ask: 'what are we working on?'"
echo ""
