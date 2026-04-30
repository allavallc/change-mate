#!/bin/bash

set -e

REPO_URL="https://raw.githubusercontent.com/allavallc/bot-horde/main"
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

# Returns 0 (true) if bot-horde/ is excluded from the repo (local-only mode).
# Matches: bot-horde, bot-horde/, /bot-horde, /bot-horde/ (with optional trailing whitespace).
# Lines starting with # are ignored. .gitignore must already exist.
is_local_only_mode() {
  [ -f .gitignore ] || return 1
  grep -qE '^[[:space:]]*/?bot-horde/?[[:space:]]*$' .gitignore
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
  if ! curl -fsSL "$REPO_URL/bot-horde/MANIFEST.json" -o "$tmp_manifest"; then
    echo -e "${RED}✗${NC} could not fetch upstream MANIFEST.json"
    rm -f "$tmp_manifest"
    return 2
  fi
  local stale
  stale=$(manifest_diff "$tmp_manifest" "bot-horde/MANIFEST.json")
  rm -f "$tmp_manifest"
  if [ -z "$stale" ]; then
    echo -e "${GREEN}✓${NC} all bot-horde files are up to date"
    return 0
  fi
  echo "stale files:"
  echo "$stale" | while IFS=$'\t' read -r path up loc; do
    echo "  • $path: local=${loc:-MISSING} → upstream=$up"
  done
  echo ""
  echo "to upgrade: BOTHORDE_UPGRADE_DOCS=yes bash setup.sh"
  return 1
}

run_upgrade_mode() {
  local tmp_manifest
  tmp_manifest=$(mktemp 2>/dev/null || echo "/tmp/cm-manifest-$$")
  if ! curl -fsSL "$REPO_URL/bot-horde/MANIFEST.json" -o "$tmp_manifest"; then
    echo -e "${RED}✗${NC} could not fetch upstream MANIFEST.json"
    rm -f "$tmp_manifest"
    return 2
  fi
  local stale
  stale=$(manifest_diff "$tmp_manifest" "bot-horde/MANIFEST.json")
  if [ -z "$stale" ]; then
    echo -e "${GREEN}✓${NC} already up to date — nothing to do"
    rm -f "$tmp_manifest"
    return 0
  fi
  local local_only=0
  if is_local_only_mode; then
    local_only=1
  fi
  local failed=0
  while IFS=$'\t' read -r path up loc; do
    [ -z "$path" ] && continue
    if [ $local_only -eq 1 ] && [ "$path" = ".github/workflows/bot-horde-rebuild-board.yml" ]; then
      echo -e "${YELLOW}~${NC} skipping $path (local-only mode — workflow not used)"
      continue
    fi
    mkdir -p "$(dirname "$path")"
    if curl -fsSL "$REPO_URL/$path" -o "$path"; then
      echo -e "${GREEN}✓${NC} updated $path (${loc:-installed} → $up)"
    else
      echo -e "${RED}✗${NC} failed to fetch $path"
      failed=1
    fi
  done <<< "$stale"
  if [ $failed -eq 0 ]; then
    mv "$tmp_manifest" bot-horde/MANIFEST.json
    echo -e "${GREEN}✓${NC} updated bot-horde/MANIFEST.json"
  else
    rm -f "$tmp_manifest"
    echo -e "${YELLOW}~${NC} some fetches failed; local MANIFEST.json left unchanged"
    return 1
  fi
}

# --- early dispatch: check / upgrade modes --------------------------------

if [ "${BOTHORDE_CHECK_UPDATES:-}" = "yes" ]; then
  run_check_mode
  exit $?
fi

if [ "${BOTHORDE_UPGRADE_DOCS:-}" = "yes" ]; then
  run_upgrade_mode
  exit $?
fi

echo ""
echo "setting up bot-horde..."
echo ""

# --- folder structure -----------------------------------------------------

mkdir -p bot-horde/backlog bot-horde/in-progress bot-horde/done bot-horde/blocked bot-horde/not-doing bot-horde/feature-sets

for d in backlog in-progress done blocked not-doing feature-sets; do
  touch "bot-horde/$d/.gitkeep"
done

echo -e "${GREEN}✓${NC} created bot-horde/ folder structure"

# --- runtime files --------------------------------------------------------

# Files installed once per repo (skipped if present).
download "bot-horde/BOTHORDE.md"          bot-horde/BOTHORDE.md
download "bot-horde/INSTALL-FAQ.md"         bot-horde/INSTALL-FAQ.md
download "bot-horde/UPDATING.md"            bot-horde/UPDATING.md
download "bot-horde/MANIFEST.json"          bot-horde/MANIFEST.json
download "bot-horde/build.sh"               bot-horde/build.sh
download "bot-horde/build_lib.py"           bot-horde/build_lib.py
download "bot-horde/config.json"            bot-horde/config.json

# The rebuild-board workflow is git-sync only. In local-only mode (bot-horde/ in
# .gitignore), it would fail on every push since bot-horde/build.sh isn't checked in.
WORKFLOW_PATH=".github/workflows/bot-horde-rebuild-board.yml"
if is_local_only_mode; then
  echo -e "${YELLOW}~${NC} local-only mode detected (bot-horde/ in .gitignore) — skipping rebuild-board workflow"
  if [ -f "$WORKFLOW_PATH" ]; then
    echo ""
    echo -e "${YELLOW}!${NC} an existing $WORKFLOW_PATH was found"
    echo "  in local-only mode it will fail on every push (build.sh isn't tracked)."
    if prompt_yn "remove it now? [y/N]" BOTHORDE_REMOVE_WORKFLOW no; then
      rm -f "$WORKFLOW_PATH"
      echo -e "${GREEN}✓${NC} removed $WORKFLOW_PATH"
    else
      echo "kept $WORKFLOW_PATH — note: it will fail on every push to main"
    fi
    echo ""
  fi
else
  download "$WORKFLOW_PATH" "$WORKFLOW_PATH"
fi

chmod +x bot-horde/build.sh 2>/dev/null || true

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
      if prompt_yn "upgrade now? [y/N]" BOTHORDE_UPGRADE_SKILL no; then
        cp "$TMP_SKILL" "$SKILL_FILE"
        echo -e "${GREEN}✓${NC} upgraded product-manager skill to v$UPSTREAM_LABEL"
      else
        echo "kept v$LOCAL_LABEL — re-run setup.sh or set BOTHORDE_UPGRADE_SKILL=yes to upgrade"
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

CM_MARKER_OPEN="<!-- bot-horde import block — managed by setup.sh; remove the block to disable bot-horde -->"
CM_MARKER_CLOSE="<!-- /bot-horde import block -->"
IMPORT_LINE="@bot-horde/BOTHORDE.md"

# Backward-compat: adopters of the previous names (Horde of Bots, change-mate)
# have stale marker blocks and stale @-imports in their CLAUDE.md. Strip those
# in-place so the fresh-add logic below produces a single clean block.
if [ -f "CLAUDE.md" ]; then
  STALE_OPENS=("<!-- horde-of-bots import block" "<!-- change-mate import block")
  STALE_CLOSES=("<!-- /horde-of-bots import block -->" "<!-- /change-mate import block -->")
  STALE_IMPORTS=("@horde-of-bots/HORDEOFBOTS.md" "@change-mate/CHANGEMATE.md")
  STALE_HASHES=("# horde-of-bots" "# change-mate")
  for i in 0 1; do
    if grep -qF "${STALE_OPENS[$i]}" CLAUDE.md; then
      awk -v open_pat="${STALE_OPENS[$i]}" -v close_pat="${STALE_CLOSES[$i]}" '
        in_block { if (index($0, close_pat)) in_block=0; next }
        index($0, open_pat) { in_block=1; next }
        { print }
      ' CLAUDE.md > CLAUDE.md.cmtmp && mv CLAUDE.md.cmtmp CLAUDE.md
      echo -e "${YELLOW}~${NC} removed stale ${STALE_OPENS[$i]/<!-- /} block from CLAUDE.md (project renamed to Bot Horde)"
    fi
    # Strip any orphan un-wrapped @-import / hash-comment line.
    for orphan in "${STALE_IMPORTS[$i]}" "${STALE_HASHES[$i]}"; do
      if grep -qxF "$orphan" CLAUDE.md; then
        grep -vxF "$orphan" CLAUDE.md > CLAUDE.md.cmtmp && mv CLAUDE.md.cmtmp CLAUDE.md
        echo -e "${YELLOW}~${NC} removed orphan '$orphan' line from CLAUDE.md"
      fi
    done
  done
fi

write_cm_block() {
  printf '%s\n# bot-horde\n%s\n%s\n' "$CM_MARKER_OPEN" "$IMPORT_LINE" "$CM_MARKER_CLOSE"
}

if [ -f "CLAUDE.md" ]; then
  if grep -qF "$CM_MARKER_OPEN" CLAUDE.md; then
    echo -e "${YELLOW}~${NC} CLAUDE.md already has bot-horde import block, skipping"
  elif grep -qF "$IMPORT_LINE" CLAUDE.md; then
    # Existing un-wrapped import — wrap it idempotently using a temp file.
    awk -v open="$CM_MARKER_OPEN" -v close="$CM_MARKER_CLOSE" -v line="$IMPORT_LINE" '
      $0 ~ "^# bot-horde$" && getline next_line && next_line == line {
        print open
        print $0
        print next_line
        print close
        next
      }
      { print }
    ' CLAUDE.md > CLAUDE.md.cmtmp && mv CLAUDE.md.cmtmp CLAUDE.md
    if grep -qF "$CM_MARKER_OPEN" CLAUDE.md; then
      echo -e "${GREEN}✓${NC} wrapped existing bot-horde import in CLAUDE.md with managed markers"
    else
      # awk pattern didn't match (different layout); append a fresh wrapped block.
      printf '\n' >> CLAUDE.md
      write_cm_block >> CLAUDE.md
      echo -e "${GREEN}✓${NC} appended managed bot-horde import block to CLAUDE.md"
    fi
  else
    printf '\n' >> CLAUDE.md
    write_cm_block >> CLAUDE.md
    echo -e "${GREEN}✓${NC} added bot-horde import block to existing CLAUDE.md"
  fi
else
  write_cm_block > CLAUDE.md
  echo -e "${GREEN}✓${NC} created CLAUDE.md"
fi

# --- deploy-ignore defaults ----------------------------------------------

CM_IGNORE_LINE="bot-horde/"
for ignore_file in .dockerignore .gcloudignore .vercelignore; do
  if [ -f "$ignore_file" ]; then
    if grep -qxF "$CM_IGNORE_LINE" "$ignore_file"; then
      echo -e "${YELLOW}~${NC} $ignore_file already excludes bot-horde/, skipping"
    else
      [ -s "$ignore_file" ] && [ "$(tail -c1 "$ignore_file" 2>/dev/null | wc -l)" = "0" ] && echo "" >> "$ignore_file"
      echo "$CM_IGNORE_LINE" >> "$ignore_file"
      echo -e "${GREEN}✓${NC} added bot-horde/ to $ignore_file"
    fi
  fi
done

# --- .gitignore guidance --------------------------------------------------

if [ -f ".gitignore" ]; then
  if is_local_only_mode; then
    echo ""
    echo -e "${YELLOW}local-only mode${NC}: bot-horde/ is gitignored — tickets won't sync between teammates."
    echo "   To switch to git-sync mode, remove the bot-horde/ line from .gitignore"
    echo "   and re-run setup.sh."
    echo ""
    LOCAL_ONLY_MARKER="# bot-horde: local-only mode (rebuild-board workflow intentionally not installed)"
    if ! grep -qF "$LOCAL_ONLY_MARKER" .gitignore; then
      [ -s ".gitignore" ] && [ "$(tail -c1 .gitignore 2>/dev/null | wc -l)" = "0" ] && echo "" >> .gitignore
      echo "$LOCAL_ONLY_MARKER" >> .gitignore
      echo -e "${GREEN}✓${NC} added local-only marker comment to .gitignore"
    fi
  else
    GIT_MARKER="# bot-horde/ is dev-only tooling; do not ignore unless using local-only mode (see bot-horde/BOTHORDE.md)"
    if ! grep -qF "$GIT_MARKER" .gitignore; then
      [ -s ".gitignore" ] && [ "$(tail -c1 .gitignore 2>/dev/null | wc -l)" = "0" ] && echo "" >> .gitignore
      echo "$GIT_MARKER" >> .gitignore
      echo -e "${GREEN}✓${NC} added dev-only-tooling marker comment to .gitignore"
    fi
  fi
fi

# --- starter board.html (best-effort) ------------------------------------

if [ ! -f bot-horde/board.html ]; then
  if command -v py >/dev/null 2>&1 || command -v python3 >/dev/null 2>&1 || command -v python >/dev/null 2>&1; then
    if bash bot-horde/build.sh >/dev/null 2>&1; then
      echo -e "${GREEN}✓${NC} generated initial bot-horde/board.html"
    else
      echo -e "${YELLOW}~${NC} build.sh failed locally — your first push will trigger CI to build the board"
    fi
  else
    echo -e "${YELLOW}~${NC} Python 3 not found — your first push will trigger CI to build the board"
  fi
fi

# --- final message --------------------------------------------------------

echo ""
echo -e "${GREEN}bot-horde is ready.${NC}"
echo ""
echo "next steps:"
echo "  1. read bot-horde/INSTALL-FAQ.md if you have questions"
echo "  2. commit and push the bot-horde/ folder + .github/workflows/ to your repo"
echo "  3. start an agent session and ask: 'what are we working on?'"
echo ""
