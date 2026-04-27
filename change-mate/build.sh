#!/bin/bash
set -e
cd "$(dirname "$0")/.."

PYTHON=""
for cmd in py python3 python; do
  if command -v "$cmd" &>/dev/null && "$cmd" -c "import sys; assert sys.version_info[0] >= 3" 2>/dev/null; then
    PYTHON="$cmd"
    break
  fi
done
if [ -z "$PYTHON" ]; then
  echo "Error: Python 3 is required. Please install it and try again." >&2
  exit 1
fi

"$PYTHON" - << 'PYEOF'
import re, json, subprocess, sys, os
from pathlib import Path
from datetime import datetime, timezone
UTC = timezone.utc

ROOT = Path.cwd()
CM = ROOT / "change-mate"
sys.path.insert(0, str(CM))
from build_lib import parse_ticket, parse_feature_set

# Read Supabase config — env vars (set by GitHub Actions secrets) take priority
_cfg_path = CM / "config.json"
_cfg = json.loads(_cfg_path.read_text()) if _cfg_path.exists() else {}
SUPABASE_URL = os.environ.get('SUPABASE_URL') or _cfg.get('supabase_url', '')
SUPABASE_PUBLISHABLE_KEY = os.environ.get('SUPABASE_PUBLISHABLE_KEY') or _cfg.get('supabase_publishable_key', '')
PROJECT_NAME = _cfg.get('project_name', '')


def detect_github_repo():
    try:
        res = subprocess.run(
            ["git", "remote", "get-url", "origin"],
            capture_output=True, text=True, timeout=5
        )
        url = res.stdout.strip()
        m = re.search(r"github\.com[:/](.+?)(?:\.git)?$", url)
        if m:
            return m.group(1)
    except Exception:
        pass
    return ""

GITHUB_REPO = detect_github_repo()



tickets = []
for folder, default_status in [
    ("backlog", "open"),
    ("in-progress", "in-progress"),
    ("done", "done"),
    ("blocked", "blocked"),
    ("not-doing", "not-doing"),
]:
    d = CM / folder
    if d.exists():
        for f in sorted(d.glob("CM-*.md")):
            tickets.append(parse_ticket(f, default_status))

feature_sets = []
sd = CM / "feature-sets"
if sd.exists():
    for f in sorted(sd.glob("feature-set-*.md")):
        feature_sets.append(parse_feature_set(f))

# Relationship analysis: inverse edge inference + orphan + cycle detection
valid_ids = {t["id"] for t in tickets}
by_id = {t["id"]: t for t in tickets}

# Inverse blocked_by: if A blocks B, B.blocked_by_inferred += [A]
inv = {tid: [] for tid in valid_ids}
for t in tickets:
    for target in t.get("blocks", []):
        if target in inv:
            inv[target].append(t["id"])

for t in tickets:
    explicit = set(t.get("blocked_by", []))
    # Only include inferred if not already explicit (dedupe — avoid showing same edge twice)
    t["blocked_by_inferred"] = [x for x in inv.get(t["id"], []) if x not in explicit]

# Orphan detection — reference to a CM-ID that doesn't exist on disk
for t in tickets:
    for field in ("related", "blocks", "blocked_by"):
        for ref in t.get(field, []):
            if ref not in valid_ids:
                print(f"[warn] {t['id']} references {ref} in {field} but {ref} does not exist", file=sys.stderr)

# Cycle detection on the blocks graph (A blocks B = A -> B)
cycles_found = []
visited = set()

def _dfs_cycles(node, path, path_set):
    for neighbor in by_id.get(node, {}).get("blocks", []):
        if neighbor not in valid_ids:
            continue
        if neighbor in path_set:
            idx = path.index(neighbor)
            cycles_found.append(path[idx:])
        elif neighbor not in visited:
            _dfs_cycles(neighbor, path + [neighbor], path_set | {neighbor})
    visited.add(node)

for _tid in sorted(valid_ids):
    if _tid not in visited:
        _dfs_cycles(_tid, [_tid], {_tid})

# Deduplicate cycles (same cycle can be discovered from different rotations)
_seen_cycles = set()
for _cycle in cycles_found:
    if not _cycle:
        continue
    _min_idx = _cycle.index(min(_cycle))
    _norm = tuple(_cycle[_min_idx:] + _cycle[:_min_idx])
    if _norm not in _seen_cycles:
        _seen_cycles.add(_norm)
        _chain = " -> ".join(_norm) + f" -> {_norm[0]}"
        print(f"[warn] cycle detected in blocks graph: {_chain}", file=sys.stderr)

data_json = json.dumps(
    {"tickets": tickets, "feature_sets": feature_sets, "generated": datetime.now(UTC).isoformat()},
    indent=2
)

cm_config_json = json.dumps({
    "supabase_url": SUPABASE_URL,
    "supabase_publishable_key": SUPABASE_PUBLISHABLE_KEY,
    "project_name": PROJECT_NAME,
}, indent=2)


def detect_head_sha():
    try:
        res = subprocess.run(
            ["git", "rev-parse", "HEAD"],
            capture_output=True, text=True, timeout=5
        )
        return res.stdout.strip()
    except Exception:
        return ""


POLL_SECONDS = _cfg.get("poll_seconds", 30)
HEAD_SHA = detect_head_sha()
poll_config_json = json.dumps({
    "repo": GITHUB_REPO,
    "poll_seconds": POLL_SECONDS,
    "head_sha": HEAD_SHA,
})

HTML = """<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="UTF-8">
<meta name="viewport" content="width=device-width, initial-scale=1.0">
<title>change-mate board</title>
<link rel="preconnect" href="https://fonts.googleapis.com">
<link rel="preconnect" href="https://fonts.gstatic.com" crossorigin>
<link href="https://fonts.googleapis.com/css2?family=Big+Shoulders+Display:wght@500;700;900&family=Inter:wght@300;400;500;600&family=JetBrains+Mono:wght@400;500&display=swap" rel="stylesheet">
<style>
:root {
  --bg: #0a0a0a;
  --bg-2: #111111;
  --ink: #f2f1ee;
  --ink-soft: #d5d3cf;
  --ink-dim: #8a8680;
  --ink-dimmer: #55514c;
  --line: #1f1d1b;
  --accent: #c4724a;
  --display: 'Big Shoulders Display', 'Inter', sans-serif;
  --sans: 'Inter', -apple-system, BlinkMacSystemFont, 'Segoe UI', sans-serif;
  --mono: 'JetBrains Mono', ui-monospace, 'SFMono-Regular', Consolas, monospace;
}
*, *::before, *::after { box-sizing: border-box; margin: 0; padding: 0; }
::selection { background: var(--accent); color: var(--bg); }
body {
  font-family: var(--sans);
  font-size: 15px;
  line-height: 1.6;
  background: var(--bg);
  color: var(--ink);
  -webkit-font-smoothing: antialiased;
  -moz-osx-font-smoothing: grayscale;
}
header {
  border-bottom: 1px solid var(--line);
  padding: 0 32px;
  height: 64px;
  display: flex;
  align-items: center;
  justify-content: space-between;
  position: sticky;
  top: 0;
  background: rgba(10,10,10,0.75);
  -webkit-backdrop-filter: blur(14px);
  backdrop-filter: blur(14px);
  z-index: 10;
}
.logo {
  font-family: var(--display);
  font-size: 1.25rem;
  font-weight: 900;
  letter-spacing: 0.05em;
  text-transform: uppercase;
  color: var(--ink);
}
.logo span { color: var(--accent); }
.header-meta {
  font-family: var(--mono);
  font-size: 0.7rem;
  font-weight: 400;
  letter-spacing: 0.15em;
  text-transform: uppercase;
  color: var(--ink-dimmer);
}
main { max-width: 1280px; margin: 0 auto; padding: 32px; }
.tabs {
  display: flex;
  gap: 0;
  margin-bottom: 32px;
  border-bottom: 1px solid var(--line);
}
.tab {
  padding: 14px 0;
  margin-right: 32px;
  margin-bottom: -1px;
  border: none;
  border-bottom: 1px solid transparent;
  background: none;
  cursor: pointer;
  font-family: var(--mono);
  font-size: 0.7rem;
  font-weight: 500;
  letter-spacing: 0.25em;
  text-transform: uppercase;
  color: var(--ink-dim);
  transition: color 0.2s ease, border-color 0.2s ease;
}
.tab:hover { color: var(--ink); }
.tab.active {
  color: var(--ink);
  border-bottom-color: var(--accent);
}
.view { display: none; }
.view.active { display: block; }
.board {
  display: grid;
  grid-template-columns: repeat(4, minmax(0, 1fr));
  gap: 0;
  border-top: 1px solid var(--line);
  border-left: 1px solid var(--line);
}
.board > div {
  border-right: 1px solid var(--line);
  border-bottom: 1px solid var(--line);
  padding: 24px;
  min-width: 0;
}
.board.show-rejected { grid-template-columns: repeat(5, minmax(0, 1fr)); }
.col-rejected { display: none; }
.board.show-rejected .col-rejected { display: block; }
.card.not-doing { opacity: 0.4; }
.card.not-doing .card-title { text-decoration: line-through; color: var(--ink-dim); }
.btn-toggle-rejected {
  padding: 8px 16px;
  border: 1px solid var(--line);
  border-radius: 0;
  cursor: pointer;
  font-family: var(--mono);
  font-size: 0.7rem;
  font-weight: 500;
  letter-spacing: 0.2em;
  text-transform: uppercase;
  background: none;
  color: var(--ink-dim);
  margin-bottom: 24px;
  transition: color 0.2s ease, border-color 0.2s ease;
}
.btn-toggle-rejected:hover { color: var(--ink); border-color: var(--ink-dim); }
.btn-toggle-rejected.active { color: var(--ink); border-color: var(--ink-dim); }
@media (max-width: 900px) { .board { grid-template-columns: minmax(0, 1fr) minmax(0, 1fr); } .board.show-rejected { grid-template-columns: minmax(0, 1fr) minmax(0, 1fr); } }
@media (max-width: 560px) { .board { grid-template-columns: 1fr; } .board.show-rejected { grid-template-columns: 1fr; } }
.col-head {
  display: flex;
  align-items: center;
  justify-content: space-between;
  margin-bottom: 20px;
}
.col-name {
  font-family: var(--mono);
  font-size: 0.7rem;
  font-weight: 500;
  letter-spacing: 0.25em;
  text-transform: uppercase;
  color: var(--accent);
  position: relative;
  padding-left: 32px;
}
.col-name::before {
  content: '';
  position: absolute;
  left: 0;
  top: 50%;
  width: 24px;
  height: 1px;
  background: var(--accent);
}
.col-count {
  font-family: var(--mono);
  font-size: 0.7rem;
  letter-spacing: 0.15em;
  color: var(--ink-dimmer);
}
.cards { display: flex; flex-direction: column; gap: 12px; }
.card {
  background: transparent;
  border: 1px solid var(--line);
  border-radius: 0;
  padding: 16px;
  cursor: pointer;
  transition: border-color 0.2s ease, background 0.2s ease;
}
.card:hover { border-color: var(--ink-dim); background: var(--bg-2); }
.card.status-open       { border: 1px solid var(--ink-dimmer); }
.card.status-done       { border: 2px solid var(--accent); }
.card.status-inprogress { position: relative; border: 1px dashed var(--accent); }
.card.status-blocked    { border: 1px dotted var(--accent); }
.card-top { display: flex; align-items: flex-start; justify-content: space-between; gap: 8px; margin-bottom: 8px; }
.card-id {
  font-family: var(--mono);
  font-size: 0.7rem;
  font-weight: 500;
  letter-spacing: 0.15em;
  text-transform: uppercase;
  color: var(--ink-dimmer);
}
.badges { display: flex; gap: 6px; flex-wrap: wrap; justify-content: flex-end; }
.badge {
  font-family: var(--mono);
  font-size: 0.65rem;
  font-weight: 500;
  letter-spacing: 0.15em;
  text-transform: uppercase;
  padding: 2px 7px;
  border: 1px solid var(--line);
  background: transparent;
  color: var(--ink-dim);
  border-radius: 0;
}
.b-critical { color: var(--accent); border-color: var(--accent); }
.b-high     { color: var(--ink); border-color: var(--ink-dim); }
.b-medium   { color: var(--ink-dim); border-color: var(--line); }
.b-low      { color: var(--ink-dimmer); border-color: var(--line); }
.b-effort   { color: var(--ink-dim); border-color: var(--line); }
.card-crab {
  display: inline-flex;
  align-items: center;
  gap: 4px;
  font-family: var(--mono);
  font-size: 0.65rem;
  font-weight: 500;
  letter-spacing: 0.15em;
  text-transform: uppercase;
  padding: 2px 8px;
  border: 1px solid var(--line);
  border-radius: 0;
  background: transparent;
  white-space: nowrap;
  max-width: 130px;
  overflow: hidden;
  text-overflow: ellipsis;
}
.cm-robot {
  position: absolute;
  width: 18px;
  height: 18px;
  pointer-events: none;
  z-index: 1;
  animation: cm-robot-walk 12s linear infinite;
}
@keyframes cm-robot-walk {
  0%   { top: -10px;             left: -10px; }
  25%  { top: -10px;             left: calc(100% - 8px); }
  50%  { top: calc(100% - 8px);  left: calc(100% - 8px); }
  75%  { top: calc(100% - 8px);  left: -10px; }
  100% { top: -10px;             left: -10px; }
}
.card-title {
  font-family: var(--display);
  font-size: 1.0625rem;
  font-weight: 700;
  line-height: 1.05;
  letter-spacing: -0.005em;
  text-transform: uppercase;
  color: var(--ink);
  margin-bottom: 8px;
  overflow-wrap: anywhere;
}
.card-assignee {
  font-family: var(--mono);
  font-size: 0.65rem;
  letter-spacing: 0.15em;
  text-transform: uppercase;
  color: var(--ink-dimmer);
}
.card-fs {
  display: inline-block;
  font-family: var(--mono);
  font-size: 0.65rem;
  font-weight: 500;
  letter-spacing: 0.15em;
  text-transform: uppercase;
  color: var(--ink-dim);
  border: 1px solid var(--line);
  border-radius: 0;
  padding: 2px 8px;
  margin-bottom: 8px;
  white-space: nowrap;
}
.card-rels { display: flex; flex-wrap: wrap; gap: 4px; margin-bottom: 8px; }
.card-rel {
  display: inline-flex;
  align-items: center;
  font-family: var(--mono);
  font-size: 0.65rem;
  font-weight: 500;
  letter-spacing: 0.1em;
  color: var(--ink-dim);
  border: 1px solid var(--line);
  border-radius: 0;
  padding: 2px 7px;
  white-space: nowrap;
}
.card-rel-more { color: var(--ink-dimmer); }
.dl-val.pre { white-space: pre-line; }
.card-detail { max-height: 0; overflow: hidden; transition: max-height 0.25s ease; }
.card.open .card-detail { max-height: 800px; }
.detail-inner {
  padding-top: 16px;
  margin-top: 16px;
  border-top: 1px solid var(--line);
  display: flex;
  flex-direction: column;
  gap: 14px;
}
.dl-label {
  font-family: var(--mono);
  font-size: 0.65rem;
  font-weight: 500;
  text-transform: uppercase;
  letter-spacing: 0.2em;
  color: var(--accent);
  margin-bottom: 6px;
}
.dl-val {
  font-family: var(--sans);
  font-size: 0.875rem;
  line-height: 1.7;
  color: var(--ink-soft);
}
.dl-list { list-style: none; font-family: var(--sans); font-size: 0.875rem; line-height: 1.7; color: var(--ink-soft); }
.dl-list li { padding-left: 14px; position: relative; margin-bottom: 4px; }
.dl-list li::before { content: ''; position: absolute; left: 0; top: 0.7em; width: 6px; height: 1px; background: var(--accent); }
.empty {
  font-family: var(--mono);
  font-size: 0.7rem;
  letter-spacing: 0.2em;
  text-transform: uppercase;
  color: var(--ink-dimmer);
  padding: 12px 0;
}
.feature-sets { display: flex; flex-direction: column; gap: 24px; }
.feature-set { border: 1px solid var(--line); border-radius: 0; }
.feature-set-head {
  padding: 20px 24px;
  display: flex;
  align-items: flex-start;
  justify-content: space-between;
  gap: 16px;
  border-bottom: 1px solid var(--line);
}
.feature-set-name {
  font-family: var(--display);
  font-size: 1.5rem;
  font-weight: 700;
  letter-spacing: 0.01em;
  text-transform: uppercase;
  color: var(--ink);
  margin-bottom: 6px;
}
.feature-set-goal {
  font-family: var(--sans);
  font-size: 0.875rem;
  color: var(--ink-dim);
  line-height: 1.6;
}
.feature-set-status {
  font-family: var(--mono);
  font-size: 0.65rem;
  font-weight: 500;
  letter-spacing: 0.2em;
  text-transform: uppercase;
  padding: 4px 10px;
  white-space: nowrap;
  background: transparent;
  border: 1px solid var(--line);
  border-radius: 0;
  color: var(--ink-dim);
  flex-shrink: 0;
}
.feature-set-prog-row {
  padding: 14px 24px;
  display: flex;
  align-items: center;
  gap: 16px;
  border-bottom: 1px solid var(--line);
}
.prog-bar { flex: 1; height: 1px; background: var(--line); border-radius: 0; position: relative; overflow: visible; }
.prog-fill { height: 1px; background: var(--accent); border-radius: 0; }
.prog-label {
  font-family: var(--mono);
  font-size: 0.65rem;
  letter-spacing: 0.2em;
  text-transform: uppercase;
  color: var(--ink-dimmer);
  white-space: nowrap;
}
.feature-set-cards { padding: 16px; display: flex; flex-wrap: wrap; gap: 12px; }
.feature-set-cards .card { width: calc(25% - 9px); min-width: 200px; }
@media (max-width: 900px) { .feature-set-cards .card { width: calc(50% - 6px); } }
@media (max-width: 560px) { .feature-set-cards .card { width: 100%; } }
.header-right { display: flex; align-items: center; gap: 24px; }
.btn-new {
  padding: 10px 20px;
  border: 1px solid var(--ink);
  border-radius: 0;
  cursor: pointer;
  font-family: var(--mono);
  font-size: 0.7rem;
  font-weight: 500;
  letter-spacing: 0.2em;
  text-transform: uppercase;
  background: transparent;
  color: var(--ink);
  white-space: nowrap;
  transition: background 0.2s ease, color 0.2s ease, border-color 0.2s ease;
}
.btn-new:hover { background: var(--accent); color: var(--bg); border-color: var(--accent); }
.settings-note { font-family: var(--sans); font-size: 0.75rem; color: var(--ink-dim); margin-top: 14px; line-height: 1.6; }
.settings-note a { color: var(--ink); }
.modal-overlay {
  position: fixed;
  inset: 0;
  background: rgba(10,10,10,0.85);
  display: flex;
  align-items: center;
  justify-content: center;
  z-index: 50;
}
.modal {
  background: var(--bg);
  border: 1px solid var(--line);
  border-radius: 0;
  padding: 32px;
  width: calc(100% - 32px);
  max-width: 480px;
  max-height: 90vh;
  overflow-y: auto;
}
.modal-title {
  font-family: var(--display);
  font-size: 1.5rem;
  font-weight: 700;
  text-transform: uppercase;
  letter-spacing: 0.01em;
  margin-bottom: 24px;
  color: var(--ink);
}
.field { margin-bottom: 20px; }
.field label {
  display: block;
  font-family: var(--mono);
  font-size: 0.65rem;
  font-weight: 500;
  text-transform: uppercase;
  letter-spacing: 0.2em;
  color: var(--ink-dim);
  margin-bottom: 8px;
}
.field input, .field select, .field textarea {
  width: 100%;
  background: transparent;
  border: none;
  border-bottom: 1px solid var(--line);
  border-radius: 0;
  padding: 8px 0;
  font-family: var(--sans);
  font-size: 0.9375rem;
  color: var(--ink);
  outline: none;
  transition: border-color 0.2s ease;
}
.field select { cursor: pointer; }
.field input:focus, .field select:focus, .field textarea:focus { border-bottom-color: var(--accent); }
.field textarea { resize: vertical; min-height: 70px; line-height: 1.6; }
.field-row { display: grid; grid-template-columns: 1fr 1fr; gap: 24px; margin-bottom: 20px; }
.field-row .field { margin-bottom: 0; }
.modal-actions { display: flex; gap: 12px; justify-content: flex-end; margin-top: 28px; padding-top: 24px; border-top: 1px solid var(--line); }
.btn {
  padding: 10px 20px;
  border: 1px solid var(--line);
  border-radius: 0;
  cursor: pointer;
  font-family: var(--mono);
  font-size: 0.7rem;
  font-weight: 500;
  letter-spacing: 0.2em;
  text-transform: uppercase;
  background: transparent;
  color: var(--ink-dim);
  transition: color 0.2s ease, border-color 0.2s ease, background 0.2s ease;
}
.btn:hover { color: var(--ink); border-color: var(--ink-dim); }
.btn-primary { color: var(--ink); border-color: var(--ink); }
.btn-primary:hover { background: var(--accent); color: var(--bg); border-color: var(--accent); }
#toast {
  position: fixed;
  bottom: 32px;
  left: 50%;
  transform: translateX(-50%) translateY(8px);
  background: var(--bg-2);
  color: var(--ink);
  border: 1px solid var(--line);
  padding: 12px 20px;
  border-radius: 0;
  font-family: var(--mono);
  font-size: 0.7rem;
  letter-spacing: 0.15em;
  text-transform: uppercase;
  max-width: 560px;
  width: calc(100% - 48px);
  text-align: center;
  opacity: 0;
  transition: opacity 0.2s ease, transform 0.2s ease;
  pointer-events: none;
  z-index: 100;
}
#toast.show { opacity: 1; transform: translateX(-50%) translateY(0); }
@keyframes cm-pulse {
  0%   { background: transparent; }
  30%  { background: rgba(196, 114, 74, 0.18); }
  100% { background: transparent; }
}
@keyframes cm-fadein {
  from { opacity: 0; transform: translateY(-8px); }
  to   { opacity: 1; transform: translateY(0); }
}
.cm-moving { animation: cm-pulse 600ms ease; }
.cm-new { animation: cm-fadein 300ms ease; }
#setup-modal .modal { max-width: 420px; }
@media (prefers-reduced-motion: reduce) {
  *, *::before, *::after { animation-duration: 0.01ms !important; transition-duration: 0.01ms !important; }
  .cm-robot { display: none; }
}
</style>
</head>
<body>
<header>
  <div style="display:flex;align-items:center;gap:10px;">
    <span class="logo">change<span>-mate</span></span>
    <span id="cm-live-indicator" style="display:none; align-items:center; gap:6px; font-family:var(--mono); font-size:0.65rem; letter-spacing:0.2em; text-transform:uppercase; color:var(--ink-dim);">
      <span style="width:6px; height:6px; border-radius:50%; background:var(--accent); display:inline-block;"></span>
      <span class="cm-live-label">polling</span>
    </span>
  </div>
  <div class="header-right">
    <span class="header-meta" id="gen-time"></span>
    <button class="btn-new" id="btn-add-story" onclick="openModal()">+ Add story</button>
  </div>
</header>
<main>
  <div class="tabs">
    <button class="tab active" data-view="board" onclick="switchTab(this)">Board</button>
    <button class="tab" data-view="feature-sets" onclick="switchTab(this)">Feature Sets</button>
  </div>
  <div class="view active" id="view-board">
    <button class="btn-toggle-rejected" id="btn-rejected" onclick="toggleRejected()" style="display:none">Show rejected</button>
    <div class="board" id="board-grid">
      <div>
        <div class="col-head"><span class="col-name">Backlog</span><span class="col-count" id="n-backlog">0</span></div>
        <div class="cards" id="c-backlog"></div>
      </div>
      <div>
        <div class="col-head"><span class="col-name">In Progress</span><span class="col-count" id="n-inprogress">0</span></div>
        <div class="cards" id="c-inprogress"></div>
      </div>
      <div>
        <div class="col-head"><span class="col-name">Done</span><span class="col-count" id="n-done">0</span></div>
        <div class="cards" id="c-done"></div>
      </div>
      <div>
        <div class="col-head"><span class="col-name">Blocked</span><span class="col-count" id="n-blocked">0</span></div>
        <div class="cards" id="c-blocked"></div>
      </div>
      <div class="col-rejected">
        <div class="col-head"><span class="col-name">Not Doing</span><span class="col-count" id="n-notdoing">0</span></div>
        <div class="cards" id="c-notdoing"></div>
      </div>
    </div>
  </div>
  <div class="view" id="view-feature-sets">
    <div class="feature-sets" id="feature-set-list"></div>
  </div>
</main>
<script>
var D = PLACEHOLDER_JSON;
var DEFAULT_REPO = PLACEHOLDER_REPO;
var CM_WRITE_URL = PLACEHOLDER_CM_WRITE_URL;
var CM_ANON_KEY = PLACEHOLDER_CM_ANON_KEY;

function esc(s) {
  return String(s || '').replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;');
}

var CRAB_COLORS = ['#ef4444','#f97316','#eab308','#22c55e','#06b6d4','#3b82f6','#8b5cf6','#ec4899'];
function crabColor(name) {
  var h = 0;
  for (var i = 0; i < name.length; i++) h = ((h << 5) - h + name.charCodeAt(i)) | 0;
  return CRAB_COLORS[Math.abs(h) % CRAB_COLORS.length];
}
function crabBadge(name) {
  if (!name) return '';
  var c = crabColor(name);
  return '<span class="card-crab" style="border-color:' + c + ';color:' + c + '">\\u{1F980} ' + esc(name) + '</span>';
}

function robotSvg(name) {
  var c = name ? crabColor(name) : '#22c55e';
  var d = -Math.random() * 12;
  var style = 'color:' + c + ';filter:drop-shadow(0 0 3px ' + c + '99);animation-delay:' + d + 's';
  return '<svg class="cm-robot" aria-hidden="true" viewBox="0 0 18 18" xmlns="http://www.w3.org/2000/svg" style="' + style + '">'
    + '<circle cx="9" cy="1" r="1" fill="currentColor"/>'
    + '<line x1="9" y1="1.5" x2="9" y2="3.5" stroke="currentColor" stroke-width="1.4" stroke-linecap="round"/>'
    + '<rect x="3" y="3.5" width="12" height="10.5" rx="2" fill="currentColor"/>'
    + '<circle cx="6.5" cy="8" r="1.3" fill="var(--bg)"/>'
    + '<circle cx="11.5" cy="8" r="1.3" fill="var(--bg)"/>'
    + '<rect x="5" y="14" width="2" height="3" fill="currentColor"/>'
    + '<rect x="11" y="14" width="2" height="3" fill="currentColor"/>'
    + '</svg>';
}

function priorityBadge(p) {
  var cls = {critical:'b-critical',high:'b-high',medium:'b-medium',low:'b-low'}[(p||'').toLowerCase()];
  return p ? '<span class="badge ' + (cls||'') + '">' + esc(p) + '</span>' : '';
}

function bulletOrProse(s) {
  if (!s) return '';
  var lines = String(s).split(/\\r?\\n/);
  var bullets = lines.filter(function(l) { return /^\\s*-\\s+/.test(l); });
  if (bullets.length && bullets.length === lines.filter(function(l) { return l.trim(); }).length) {
    return '<ul class="dl-list">'
      + bullets.map(function(l) { return '<li>' + esc(l.replace(/^\\s*-\\s+/, '')) + '</li>'; }).join('')
      + '</ul>';
  }
  return '<div class="dl-val pre">' + esc(s) + '</div>';
}

function detailRow(label, content) {
  if (!content) return '';
  return '<div><div class="dl-label">' + label + '</div>' + content + '</div>';
}

function buildRelChips(t) {
  var all = [];
  (t.related || []).forEach(function(id) { all.push({kind:'related', id:id, prefix:'\\u2194'}); });
  (t.blocks || []).forEach(function(id) { all.push({kind:'blocks', id:id, prefix:'\\u2192'}); });
  var bb = {};
  (t.blocked_by || []).forEach(function(id) { bb[id] = true; });
  (t.blocked_by_inferred || []).forEach(function(id) { bb[id] = true; });
  Object.keys(bb).forEach(function(id) { all.push({kind:'blocked_by', id:id, prefix:'\\u2190'}); });
  return all;
}

function relChipsFaceHTML(chips, cap) {
  if (!chips.length) return '';
  var visible = chips.slice(0, cap);
  var extra = chips.length - visible.length;
  var html = visible.map(function(c) {
    var title = (c.kind === 'related' ? 'Related to ' : c.kind === 'blocks' ? 'Blocks ' : 'Blocked by ') + c.id;
    return '<span class="card-rel" title="' + esc(title) + '">' + c.prefix + ' ' + esc(c.id) + '</span>';
  }).join('');
  if (extra > 0) html += '<span class="card-rel card-rel-more">+' + extra + ' more</span>';
  return '<div class="card-rels">' + html + '</div>';
}

function relDetailHTML(chips) {
  if (!chips.length) return '';
  var groups = {related: [], blocks: [], blocked_by: []};
  chips.forEach(function(c) { groups[c.kind].push(c.id); });
  var parts = [];
  if (groups.related.length)    parts.push('<div><div class="dl-label">Related</div><div class="dl-val">'    + groups.related.map(esc).join(', ')    + '</div></div>');
  if (groups.blocks.length)     parts.push('<div><div class="dl-label">Blocks</div><div class="dl-val">'     + groups.blocks.map(esc).join(', ')     + '</div></div>');
  if (groups.blocked_by.length) parts.push('<div><div class="dl-label">Blocked by</div><div class="dl-val">' + groups.blocked_by.map(esc).join(', ') + '</div></div>');
  return parts.join('');
}

function cardHTML(t, isRejected) {
  var rejClass = (isRejected || t.status === 'not-doing') ? ' not-doing' : '';
  var statusClass = '';
  if (t.status === 'done') statusClass = ' status-done';
  else if (t.status === 'in-progress') statusClass = ' status-inprogress';
  else if (t.status === 'blocked') statusClass = ' status-blocked';
  else if (t.status === 'open') statusClass = ' status-open';
  var fsChip = t.feature_set ? '<div class="card-fs">' + esc(t.feature_set) + '</div>' : '';
  var relChips = buildRelChips(t);
  var relFace = relChipsFaceHTML(relChips, 3);
  var relDetail = relDetailHTML(relChips);
  var assignee = t.assigned_to ? '<div class="card-assignee">' + esc(t.assigned_to) + '</div>' : '';

  var goal  = t.goal  ? '<div><div class="dl-label">Goal</div><div class="dl-val">'  + esc(t.goal)  + '</div></div>' : '';
  var why   = t.why   ? '<div><div class="dl-label">Why</div><div class="dl-val">'   + esc(t.why)   + '</div></div>' : '';
  var dw = '';
  if (t.done_when && t.done_when.length) {
    dw = '<div><div class="dl-label">Done when</div><ul class="dl-list">'
      + t.done_when.map(function(d) { return '<li>' + esc(d) + '</li>'; }).join('')
      + '</ul></div>';
  }
  var desired = detailRow('Desired output', bulletOrProse(t.desired_output));
  var success = detailRow('Success signals', bulletOrProse(t.success_signals));
  var failure = detailRow('Failure signals', bulletOrProse(t.failure_signals));
  var tests   = detailRow('Tests', bulletOrProse(t.tests));
  var notes = t.notes ? '<div><div class="dl-label">Notes</div><div class="dl-val pre">' + esc(t.notes) + '</div></div>' : '';
  var rejection = (t.rejection_reason && t.rejection_reason.toLowerCase() !== 'n/a')
    ? '<div><div class="dl-label">Rejection reason</div><div class="dl-val">' + esc(t.rejection_reason) + '</div></div>'
    : '';

  var detail = goal + why + dw + desired + success + failure + tests + relDetail + notes + rejection;
  var robot = (t.status === 'in-progress') ? robotSvg(t.assigned_to) : '';
  return '<div class="card' + rejClass + statusClass + '" onclick="toggleCard(this)">'
    + robot
    + '<div class="card-top">'
    + '<span class="card-id">' + esc(t.id) + '</span>'
    + '<div class="badges">' + crabBadge(t.assigned_to) + priorityBadge(t.priority) + (t.effort ? '<span class="badge b-effort">' + esc(t.effort) + '</span>' : '') + '</div>'
    + '</div>'
    + '<div class="card-title">' + esc(t.title || t.id) + '</div>'
    + fsChip
    + relFace
    + assignee
    + (detail ? '<div class="card-detail"><div class="detail-inner">' + detail + '</div></div>' : '')
    + '</div>';
}

function toggleCard(el) {
  el.classList.toggle('open');
}

function toggleRejected() {
  var btn = document.getElementById('btn-rejected');
  var board = document.getElementById('board-grid');
  var showing = board.classList.toggle('show-rejected');
  btn.textContent = showing ? 'Hide rejected' : 'Show rejected';
  btn.classList.toggle('active', showing);
}

function switchTab(btn) {
  var view = btn.getAttribute('data-view');
  document.querySelectorAll('.tab').forEach(function(b) { b.classList.toggle('active', b === btn); });
  document.querySelectorAll('.view').forEach(function(v) { v.classList.toggle('active', v.id === 'view-' + view); });
}

function render() {
  var gen = D.generated ? new Date(D.generated).toLocaleString() : '';
  if (gen) document.getElementById('gen-time').textContent = 'generated ' + gen;

  var buckets = {open:[], 'in-progress':[], done:[], blocked:[], 'not-doing':[]};
  D.tickets.forEach(function(t) { if (buckets[t.status]) buckets[t.status].push(t); });
  var colKeys = {open:'backlog','in-progress':'inprogress',done:'done',blocked:'blocked'};
  Object.keys(colKeys).forEach(function(status) {
    var list = buckets[status];
    var k = colKeys[status];
    document.getElementById('c-'+k).innerHTML = list.length ? list.map(function(t) { return cardHTML(t); }).join('') : '<div class="empty">No tickets</div>';
    document.getElementById('n-'+k).textContent = list.length;
  });
  var ndList = buckets['not-doing'];
  document.getElementById('c-notdoing').innerHTML = ndList.length ? ndList.map(function(t) { return cardHTML(t, true); }).join('') : '<div class="empty">No tickets</div>';
  document.getElementById('n-notdoing').textContent = ndList.length;
  if (ndList.length) document.getElementById('btn-rejected').style.display = '';

  var byId = {};
  D.tickets.forEach(function(t) { byId[t.id] = t; });
  var assigned = {};
  D.feature_sets.forEach(function(fs) { fs.tickets.forEach(function(id) { assigned[id] = true; }); });
  var unassigned = D.tickets.filter(function(t) { return !assigned[t.id]; });
  var sections = D.feature_sets.slice();
  if (unassigned.length) {
    sections.push({id:'__unassigned', name:'Unassigned', goal:'', status:'', tickets:unassigned.map(function(t){return t.id;})});
  }

  var featureSetList = document.getElementById('feature-set-list');
  if (!sections.length) {
    featureSetList.innerHTML = '<div class="empty">No feature sets yet.</div>';
    return;
  }

  featureSetList.innerHTML = sections.map(function(featureSet) {
    var list = featureSet.tickets.map(function(id) { return byId[id]; }).filter(Boolean);
    var done = list.filter(function(t) { return t.status === 'done'; }).length;
    var total = list.filter(function(t) { return t.status !== 'not-doing'; }).length;
    var pct = total ? Math.round(done / total * 100) : 0;
    var isUnassigned = featureSet.id === '__unassigned';
    var progRow = !isUnassigned
      ? '<div class="feature-set-prog-row"><div class="prog-bar"><div class="prog-fill" style="width:' + pct + '%"></div></div><span class="prog-label">' + done + ' / ' + total + ' tickets done</span></div>'
      : '';
    var statusBadge = featureSet.status ? '<span class="feature-set-status">' + esc(featureSet.status) + '</span>' : '';
    return '<div class="feature-set">'
      + '<div class="feature-set-head"><div>'
      + '<div class="feature-set-name">' + esc(featureSet.name) + '</div>'
      + (featureSet.goal ? '<div class="feature-set-goal">' + esc(featureSet.goal) + '</div>' : '')
      + '</div>' + statusBadge + '</div>'
      + progRow
      + '<div class="feature-set-cards">' + (list.length ? list.map(function(t) { return cardHTML(t); }).join('') : '<div class="empty">No tickets</div>') + '</div>'
      + '</div>';
  }).join('');
}

render();

function openModal() {
  var sel = document.getElementById('f-featureset');
  sel.innerHTML = '<option value="">None</option>'
    + D.feature_sets.map(function(s) { return '<option value="' + esc(s.id) + '">' + esc(s.name) + '</option>'; }).join('');
  document.getElementById('modal').style.display = 'flex';
  setTimeout(function() { document.getElementById('f-title').focus(); }, 50);
}

function closeModal() {
  document.getElementById('modal').style.display = 'none';
  ['f-title','f-assigned','f-goal','f-why','f-done','f-notes'].forEach(function(id) {
    document.getElementById(id).value = '';
  });
  document.getElementById('f-priority').value = '';
  document.getElementById('f-effort').value = '';
  document.getElementById('f-featureset').value = '';
}

function getGithubToken() { return localStorage.getItem('cm_github_token') || ''; }
function setGithubToken(t) { localStorage.setItem('cm_github_token', t); }
function clearGithubToken() { localStorage.removeItem('cm_github_token'); }
function getAgentName() { return localStorage.getItem('cm_agent_name') || ''; }
function setAgentName(n) { localStorage.setItem('cm_agent_name', n); }

function promptSetup(onSuccess, errorMsg) {
  var modal = document.getElementById('setup-modal');
  var nameInput = document.getElementById('s-name');
  var tokenInput = document.getElementById('s-token');
  var err = document.getElementById('s-error');
  nameInput.value = getAgentName();
  tokenInput.value = '';
  if (errorMsg) { err.textContent = errorMsg; err.style.display = 'block'; }
  else { err.style.display = 'none'; }
  modal.style.display = 'flex';
  modal._onSuccess = onSuccess;
  setTimeout(function() { (getAgentName() ? tokenInput : nameInput).focus(); }, 50);
}

function submitSetup() {
  var nameInput = document.getElementById('s-name');
  var tokenInput = document.getElementById('s-token');
  var name = nameInput.value.trim();
  var token = tokenInput.value.trim();
  if (!name) { nameInput.focus(); return; }
  if (!token) { tokenInput.focus(); return; }
  setAgentName(name);
  setGithubToken(token);
  var modal = document.getElementById('setup-modal');
  var cb = modal._onSuccess;
  modal.style.display = 'none';
  if (cb) cb();
}

function closeSetupModal() {
  document.getElementById('setup-modal').style.display = 'none';
}

async function createStory() {
  var title = document.getElementById('f-title').value.trim();
  if (!title) { document.getElementById('f-title').focus(); return; }
  var priority = document.getElementById('f-priority').value;
  var effort   = document.getElementById('f-effort').value;
  if (!priority || !effort) { showToast('Priority and effort are required.'); return; }

  var token = getGithubToken();
  if (!token) { promptSetup(function() { createStory(); }); return; }

  var goal    = document.getElementById('f-goal').value.trim();
  var why     = document.getElementById('f-why').value.trim();
  var doneRaw = document.getElementById('f-done').value.trim();
  var notes   = document.getElementById('f-notes').value.trim();
  var fsId    = document.getElementById('f-featureset').value;

  var payload = { title: title, goal: goal || 'TBD', done_when: doneRaw || 'TBD', priority: priority, effort: effort };
  if (why) payload.why = why;
  if (notes) payload.notes = notes;
  if (fsId) {
    var matchedFs = D.feature_sets.filter(function(fs) { return fs.id === fsId; })[0];
    if (matchedFs) payload.feature_set = matchedFs.name;
  }

  var btn = document.querySelector('#modal .btn-primary');
  var origText = btn.textContent;
  btn.textContent = 'Creating...';
  btn.disabled = true;

  try {
    console.log('[cm-write] POST', CM_WRITE_URL, 'payload:', payload);
    var res = await fetch(CM_WRITE_URL, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json', 'Authorization': 'Bearer ' + CM_ANON_KEY },
      body: JSON.stringify({ github_token: token, actor_name: getAgentName(), payload: payload })
    });
    var data = await res.json().catch(function() { return {}; });
    console.log('[cm-write] response', res.status, data);

    if (res.status === 403) {
      clearGithubToken();
      closeModal();
      promptSetup(function() { openModal(); }, data.error || 'Access denied. Check your GitHub token.');
      return;
    }
    if (!res.ok) {
      var msg = (data.error || 'HTTP ' + res.status) + (data.detail ? ' — ' + data.detail : '');
      console.error('[cm-write] failed:', msg, data);
      showToast('Error: ' + msg);
      return;
    }

    closeModal();
    showToast(data.ticket_id + ' created in backlog.');
  } catch(e) {
    console.error('[cm-write] network error:', e);
    showToast('Network error: ' + e.message);
  } finally {
    btn.textContent = origText;
    btn.disabled = false;
  }
}

var _toastTimer;
function showToast(msg) {
  var el = document.getElementById('toast');
  el.textContent = msg;
  el.classList.add('show');
  clearTimeout(_toastTimer);
  _toastTimer = setTimeout(function() { el.classList.remove('show'); }, 5000);
}

document.addEventListener('keydown', function(e) {
  if (e.key === 'Escape') { closeModal(); closeSetupModal(); }
});
</script>
<script id="cm-poll-config" type="application/json">PLACEHOLDER_POLL_CONFIG</script>
<script>
(function() {
  // Poll the GitHub commits API; if HEAD on main changed, reload the page.
  // Auth: user's PAT from localStorage (also used by Add Story); falls back to anonymous for public repos.
  var cfg = JSON.parse(document.getElementById('cm-poll-config').textContent);
  if (!cfg.repo) {
    console.warn('[cm-poll] no repo detected, polling disabled');
    return;
  }

  var intervalSec = Math.max(10, parseInt(cfg.poll_seconds, 10) || 30);
  var indicator = document.getElementById('cm-live-indicator');
  if (indicator) {
    indicator.style.display = 'flex';
    var label = indicator.querySelector('.cm-live-label');
    if (label) label.textContent = 'polling';
  }

  var lastSha = cfg.head_sha || null;
  var consecutiveFailures = 0;

  function getToken() { return localStorage.getItem('cm_github_token') || ''; }

  async function pollOnce() {
    if (document.hidden) return;
    try {
      var headers = { 'Accept': 'application/vnd.github+json' };
      var token = getToken();
      if (token) headers['Authorization'] = 'Bearer ' + token;
      var res = await fetch('https://api.github.com/repos/' + cfg.repo + '/commits/main', { headers: headers });
      if (res.status === 403) {
        console.warn('[cm-poll] rate limited, backing off');
        consecutiveFailures++;
        return;
      }
      if (!res.ok) {
        console.warn('[cm-poll] HTTP', res.status);
        consecutiveFailures++;
        return;
      }
      consecutiveFailures = 0;
      var body = await res.json();
      var sha = body && body.sha;
      if (!sha) return;
      if (lastSha && sha !== lastSha) {
        console.log('[cm-poll] HEAD changed', lastSha, '->', sha, '— reloading');
        location.reload();
        return;
      }
      lastSha = sha;
    } catch (e) {
      console.warn('[cm-poll] error', e);
      consecutiveFailures++;
    }
  }

  // Initial poll + interval
  pollOnce();
  setInterval(function() {
    if (consecutiveFailures > 5) return; // give up after sustained failures; user can refresh manually
    pollOnce();
  }, intervalSec * 1000);

  // Fast-path on tab visibility return
  document.addEventListener('visibilitychange', function() {
    if (!document.hidden) pollOnce();
  });
})();
</script>
<div id="modal" class="modal-overlay" style="display:none" onclick="if(event.target===this)closeModal()">
  <div class="modal">
    <div class="modal-title">New story</div>
    <div class="field">
      <label>Title</label>
      <input type="text" id="f-title" placeholder="What needs to happen?">
    </div>
    <div class="field-row">
      <div class="field">
        <label>Priority</label>
        <select id="f-priority">
          <option value="">—</option>
          <option>Low</option>
          <option>Medium</option>
          <option>High</option>
          <option>Critical</option>
        </select>
      </div>
      <div class="field">
        <label>Effort</label>
        <select id="f-effort">
          <option value="">—</option>
          <option>XS</option>
          <option>S</option>
          <option>M</option>
          <option>L</option>
          <option>XL</option>
        </select>
      </div>
    </div>
    <div class="field-row">
      <div class="field">
        <label>Feature set</label>
        <select id="f-featureset"></select>
      </div>
      <div class="field">
        <label>Assigned to</label>
        <input type="text" id="f-assigned" placeholder="Name or handle">
      </div>
    </div>
    <div class="field">
      <label>Goal</label>
      <textarea id="f-goal" placeholder="One sentence: what does this do?"></textarea>
    </div>
    <div class="field">
      <label>Why</label>
      <textarea id="f-why" placeholder="Why does this matter?"></textarea>
    </div>
    <div class="field">
      <label>Done when</label>
      <textarea id="f-done" placeholder="One criterion per line"></textarea>
    </div>
    <div class="field">
      <label>Notes</label>
      <textarea id="f-notes" placeholder="Constraints, gotchas, decisions..."></textarea>
    </div>
    <div class="modal-actions">
      <button class="btn" onclick="closeModal()">Cancel</button>
      <button class="btn btn-primary" onclick="createStory()">Create story</button>
    </div>
  </div>
</div>
<div id="setup-modal" class="modal-overlay" style="display:none" onclick="if(event.target===this)closeSetupModal()">
  <div class="modal">
    <div class="modal-title">Connect to GitHub</div>
    <div class="field">
      <label>Your name</label>
      <input type="text" id="s-name" placeholder="e.g. Ada, crabFather, Agent 7">
    </div>
    <div class="field">
      <label>GitHub token</label>
      <input type="password" id="s-token" placeholder="github_pat_..." onkeydown="if(event.key==='Enter')submitSetup()">
    </div>
    <p id="s-error" style="color:#991b1b;font-size:12px;margin-bottom:8px;display:none"></p>
    <p class="settings-note">One-time setup. Create a token at <a href="https://github.com/settings/tokens?type=beta" target="_blank" style="color:var(--text2)">github.com/settings/tokens</a> with <strong>Contents: Read and write</strong> on this repo. Stored in your browser only.</p>
    <div class="modal-actions">
      <button class="btn" onclick="closeSetupModal()">Cancel</button>
      <button class="btn btn-primary" onclick="submitSetup()">Connect</button>
    </div>
  </div>
</div>
<div id="toast"></div>
</body>
</html>"""

_cm_write_url = (SUPABASE_URL.rstrip('/') + '/functions/v1/cm-write') if SUPABASE_URL else ''
output = (HTML
    .replace("PLACEHOLDER_JSON", data_json)
    .replace("PLACEHOLDER_REPO", json.dumps(GITHUB_REPO))
    .replace("PLACEHOLDER_CM_WRITE_URL", json.dumps(_cm_write_url))
    .replace("PLACEHOLDER_CM_ANON_KEY", json.dumps(SUPABASE_PUBLISHABLE_KEY))
    .replace("PLACEHOLDER_CONFIG", cm_config_json)
    .replace("PLACEHOLDER_POLL_CONFIG", poll_config_json))
Path("change-mate/board.html").write_text(output, encoding="utf-8")
print("change-mate/board.html updated")
PYEOF
