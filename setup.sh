#!/bin/bash

set -e

REPO_URL="https://raw.githubusercontent.com/allavallc/change-mate/main"
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

# --- helpers --------------------------------------------------------------

is_tty() { [ -t 0 ]; }

prompt_yn() {
  # $1 = prompt text, $2 = env var override name, $3 = default (yes|no)
  local prompt="$1" env_var="$2" default="$3"
  local override="${!env_var:-}"
  if [ -n "$override" ]; then
    case "$override" in
      yes|y|YES|Y|true|TRUE|1) return 0 ;;
      no|n|NO|N|false|FALSE|0) return 1 ;;
    esac
  fi
  if ! is_tty; then
    if [ "$default" = "yes" ]; then return 0; else return 1; fi
  fi
  local reply
  read -r -p "$prompt " reply
  case "$reply" in
    y|Y|yes|YES) return 0 ;;
    *) return 1 ;;
  esac
}

download() {
  # $1 = remote path under REPO_URL, $2 = local path. Skips if local exists.
  local remote="$1" local_path="$2"
  if [ -f "$local_path" ]; then
    echo -e "${YELLOW}~${NC} $local_path already present, skipping"
    return 0
  fi
  mkdir -p "$(dirname "$local_path")"
  if curl -fsSL "$REPO_URL/$remote" -o "$local_path"; then
    echo -e "${GREEN}✓${NC} downloaded $local_path"
  else
    echo -e "${RED}✗${NC} failed to download $remote — check your network"
    return 1
  fi
}

skill_version() {
  # extract `version: X.Y.Z` from frontmatter of a SKILL.md, or empty if missing
  [ -f "$1" ] && grep -E '^version:' "$1" | head -1 | sed 's/^version:[[:space:]]*//' | tr -d '\r' || true
}

py_cmd() {
  for cmd in py python3 python; do
    if command -v "$cmd" >/dev/null 2>&1 && "$cmd" -c "import sys; assert sys.version_info[0] >= 3" 2>/dev/null; then
      echo "$cmd"
      return 0
    fi
  done
  return 1
}

# Diff upstream manifest against local. Outputs tab-separated `path<TAB>upstream<TAB>local` per stale file.
manifest_diff() {
  local upstream="$1" local_m="$2"
  local pyc
  pyc=$(py_cmd) || { echo "[manifest] need Python 3 to parse manifest" >&2; return 1; }
  "$pyc" - "$upstream" "$local_m" <<'PYEOF'
import json, os, sys
up_path, loc_path = sys.argv[1], sys.argv[2]
up = json.load(open(up_path))
loc = {}
if os.path.exists(loc_path):
    try:
        loc = json.load(open(loc_path)).get("files", {})
    except Exception:
        loc = {}
for path, ver in up.get("files", {}).items():
    local_ver = loc.get(path, "")
    if ver != local_ver:
        print(f"{path}\t{ver}\t{local_ver}")
PYEOF
}

run_check_mode() {
  local tmp_manifest
  tmp_manifest=$(mktemp 2>/dev/null || echo "/tmp/cm-manifest-$$")
  if ! curl -fsSL "$REPO_URL/change-mate/MANIFEST.json" -o "$tmp_manifest"; then
    echo -e "${RED}✗${NC} could not fetch upstream MANIFEST.json"
    rm -f "$tmp_manifest"
    return 2
  fi
  local stale
  stale=$(manifest_diff "$tmp_manifest" "change-mate/MANIFEST.json")
  rm -f "$tmp_manifest"
  if [ -z "$stale" ]; then
    echo -e "${GREEN}✓${NC} all change-mate files are up to date"
    return 0
  fi
  echo "stale files:"
  echo "$stale" | while IFS=$'\t' read -r path up loc; do
    echo "  • $path: local=${loc:-MISSING} → upstream=$up"
  done
  echo ""
  echo "to upgrade: CHANGEMATE_UPGRADE_DOCS=yes bash setup.sh"
  return 1
}

run_upgrade_mode() {
  local tmp_manifest
  tmp_manifest=$(mktemp 2>/dev/null || echo "/tmp/cm-manifest-$$")
  if ! curl -fsSL "$REPO_URL/change-mate/MANIFEST.json" -o "$tmp_manifest"; then
    echo -e "${RED}✗${NC} could not fetch upstream MANIFEST.json"
    rm -f "$tmp_manifest"
    return 2
  fi
  local stale
  stale=$(manifest_diff "$tmp_manifest" "change-mate/MANIFEST.json")
  if [ -z "$stale" ]; then
    echo -e "${GREEN}✓${NC} already up to date — nothing to do"
    rm -f "$tmp_manifest"
    return 0
  fi
  local failed=0
  while IFS=$'\t' read -r path up loc; do
    [ -z "$path" ] && continue
    mkdir -p "$(dirname "$path")"
    if curl -fsSL "$REPO_URL/$path" -o "$path"; then
      echo -e "${GREEN}✓${NC} updated $path (${loc:-installed} → $up)"
    else
      echo -e "${RED}✗${NC} failed to fetch $path"
      failed=1
    fi
  done <<< "$stale"
  if [ $failed -eq 0 ]; then
    mv "$tmp_manifest" change-mate/MANIFEST.json
    echo -e "${GREEN}✓${NC} updated change-mate/MANIFEST.json"
  else
    rm -f "$tmp_manifest"
    echo -e "${YELLOW}~${NC} some fetches failed; local MANIFEST.json left unchanged"
    return 1
  fi
}

# --- early dispatch: check / upgrade modes --------------------------------

if [ "${CHANGEMATE_CHECK_UPDATES:-}" = "yes" ]; then
  run_check_mode
  exit $?
fi

if [ "${CHANGEMATE_UPGRADE_DOCS:-}" = "yes" ]; then
  run_upgrade_mode
  exit $?
fi

echo ""
echo "setting up change-mate..."
echo ""

# --- folder structure -----------------------------------------------------

mkdir -p change-mate/backlog change-mate/in-progress change-mate/done change-mate/blocked change-mate/not-doing change-mate/feature-sets

for d in backlog in-progress done blocked not-doing feature-sets; do
  touch "change-mate/$d/.gitkeep"
done

echo -e "${GREEN}✓${NC} created change-mate/ folder structure"

# --- legacy migration -----------------------------------------------------

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
  if prompt_yn "migrate now? [y/N]" CHANGEMATE_AUTO_MIGRATE no; then
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
    if is_tty; then
      echo "skipped migration — nothing changed."
    else
      echo "skipped migration — stdin is not a TTY. set CHANGEMATE_AUTO_MIGRATE=yes to auto-migrate, or re-run interactively."
    fi
  fi
  echo ""
fi

# --- runtime files --------------------------------------------------------

# Files installed once per repo (skipped if present).
download "change-mate/CHANGEMATE.md"          change-mate/CHANGEMATE.md
download "change-mate/INSTALL-FAQ.md"         change-mate/INSTALL-FAQ.md
download "change-mate/MANIFEST.json"          change-mate/MANIFEST.json
download "change-mate/build.sh"               change-mate/build.sh
download "change-mate/build_lib.py"           change-mate/build_lib.py
download "change-mate/config.json"            change-mate/config.json
download ".github/workflows/change-mate-rebuild-board.yml" .github/workflows/change-mate-rebuild-board.yml

chmod +x change-mate/build.sh 2>/dev/null || true

# --- product-manager skill (global, ~/.claude/skills/) --------------------

SKILL_DIR="$HOME/.claude/skills/product-manager"
SKILL_FILE="$SKILL_DIR/SKILL.md"
TMP_SKILL=$(mktemp 2>/dev/null || echo "/tmp/cm-skill-$$")

mkdir -p "$SKILL_DIR"

# Always fetch the upstream copy to compare versions.
if curl -fsSL "$REPO_URL/skills/product-manager/SKILL.md" -o "$TMP_SKILL" 2>/dev/null; then
  UPSTREAM_VERSION=$(skill_version "$TMP_SKILL")
  if [ -f "$SKILL_FILE" ]; then
    LOCAL_VERSION=$(skill_version "$SKILL_FILE")
    if [ "$LOCAL_VERSION" = "$UPSTREAM_VERSION" ] && [ -n "$LOCAL_VERSION" ]; then
      echo -e "${YELLOW}~${NC} product-manager skill v$LOCAL_VERSION already installed"
    else
      LOCAL_LABEL="${LOCAL_VERSION:-untagged}"
      UPSTREAM_LABEL="${UPSTREAM_VERSION:-untagged}"
      echo ""
      echo -e "${YELLOW}skill upgrade available:${NC} local v$LOCAL_LABEL → upstream v$UPSTREAM_LABEL"
      if prompt_yn "upgrade now? [y/N]" CHANGEMATE_UPGRADE_SKILL no; then
        cp "$TMP_SKILL" "$SKILL_FILE"
        echo -e "${GREEN}✓${NC} upgraded product-manager skill to v$UPSTREAM_LABEL"
      else
        echo "kept v$LOCAL_LABEL — re-run setup.sh or set CHANGEMATE_UPGRADE_SKILL=yes to upgrade"
      fi
    fi
  else
    cp "$TMP_SKILL" "$SKILL_FILE"
    echo -e "${GREEN}✓${NC} installed product-manager skill v${UPSTREAM_VERSION:-untagged} to $SKILL_FILE"
  fi
  rm -f "$TMP_SKILL"
else
  echo -e "${YELLOW}~${NC} could not fetch product-manager skill (offline?), skipping"
fi

# --- CLAUDE.md import (wrapped in markers) --------------------------------

CM_MARKER_OPEN="<!-- change-mate import block — managed by setup.sh; remove the block to disable change-mate -->"
CM_MARKER_CLOSE="<!-- /change-mate import block -->"
IMPORT_LINE="@change-mate/CHANGEMATE.md"

write_cm_block() {
  printf '%s\n# change-mate\n%s\n%s\n' "$CM_MARKER_OPEN" "$IMPORT_LINE" "$CM_MARKER_CLOSE"
}

if [ -f "CLAUDE.md" ]; then
  if grep -qF "$CM_MARKER_OPEN" CLAUDE.md; then
    echo -e "${YELLOW}~${NC} CLAUDE.md already has change-mate import block, skipping"
  elif grep -qF "$IMPORT_LINE" CLAUDE.md; then
    # Existing un-wrapped import — wrap it idempotently using a temp file.
    awk -v open="$CM_MARKER_OPEN" -v close="$CM_MARKER_CLOSE" -v line="$IMPORT_LINE" '
      $0 ~ "^# change-mate$" && getline next_line && next_line == line {
        print open
        print $0
        print next_line
        print close
        next
      }
      { print }
    ' CLAUDE.md > CLAUDE.md.cmtmp && mv CLAUDE.md.cmtmp CLAUDE.md
    if grep -qF "$CM_MARKER_OPEN" CLAUDE.md; then
      echo -e "${GREEN}✓${NC} wrapped existing change-mate import in CLAUDE.md with managed markers"
    else
      # awk pattern didn't match (different layout); append a fresh wrapped block.
      printf '\n' >> CLAUDE.md
      write_cm_block >> CLAUDE.md
      echo -e "${GREEN}✓${NC} appended managed change-mate import block to CLAUDE.md"
    fi
  else
    printf '\n' >> CLAUDE.md
    write_cm_block >> CLAUDE.md
    echo -e "${GREEN}✓${NC} added change-mate import block to existing CLAUDE.md"
  fi
else
  write_cm_block > CLAUDE.md
  echo -e "${GREEN}✓${NC} created CLAUDE.md"
fi

# --- deploy-ignore defaults ----------------------------------------------

CM_IGNORE_LINE="change-mate/"
for ignore_file in .dockerignore .gcloudignore .vercelignore; do
  if [ -f "$ignore_file" ]; then
    if grep -qxF "$CM_IGNORE_LINE" "$ignore_file"; then
      echo -e "${YELLOW}~${NC} $ignore_file already excludes change-mate/, skipping"
    else
      [ -s "$ignore_file" ] && [ "$(tail -c1 "$ignore_file" 2>/dev/null | wc -l)" = "0" ] && echo "" >> "$ignore_file"
      echo "$CM_IGNORE_LINE" >> "$ignore_file"
      echo -e "${GREEN}✓${NC} added change-mate/ to $ignore_file"
    fi
  fi
done

# --- .gitignore guidance --------------------------------------------------

if [ -f ".gitignore" ]; then
  if grep -qE "^change-mate" .gitignore; then
    echo ""
    echo -e "⚠️  WARNING: change-mate/ is in your .gitignore"
    echo "   Tickets won't sync between teammates until you remove it."
    echo "   Remove this line from .gitignore: change-mate"
    echo ""
  fi
  GIT_MARKER="# change-mate/ is dev-only tooling; do not ignore unless using local-only mode (see change-mate/CHANGEMATE.md)"
  if ! grep -qF "$GIT_MARKER" .gitignore; then
    [ -s ".gitignore" ] && [ "$(tail -c1 .gitignore 2>/dev/null | wc -l)" = "0" ] && echo "" >> .gitignore
    echo "$GIT_MARKER" >> .gitignore
    echo -e "${GREEN}✓${NC} added dev-only-tooling marker comment to .gitignore"
  fi
fi

# --- starter board.html (best-effort) ------------------------------------

if [ ! -f change-mate/board.html ]; then
  if command -v py >/dev/null 2>&1 || command -v python3 >/dev/null 2>&1 || command -v python >/dev/null 2>&1; then
    if bash change-mate/build.sh >/dev/null 2>&1; then
      echo -e "${GREEN}✓${NC} generated initial change-mate/board.html"
    else
      echo -e "${YELLOW}~${NC} build.sh failed locally — your first push will trigger CI to build the board"
    fi
  else
    echo -e "${YELLOW}~${NC} Python 3 not found — your first push will trigger CI to build the board"
  fi
fi

# --- final message --------------------------------------------------------

echo ""
echo -e "${GREEN}change-mate is ready.${NC}"
echo ""
echo "next steps:"
echo "  1. read change-mate/INSTALL-FAQ.md if you have questions"
echo "  2. commit and push the change-mate/ folder + .github/workflows/ to your repo"
echo "  3. start an agent session and ask: 'what are we working on?'"
echo ""
