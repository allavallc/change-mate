#!/bin/bash
set -e
cd "$(dirname "$0")"

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
sys.path.insert(0, str(ROOT))
from build_lib import parse_ticket, parse_feature_set

# Read Supabase config — env vars (set by GitHub Actions secrets) take priority
_cfg_path = ROOT / "change-mate-config.json"
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

data_json = json.dumps(
    {"tickets": tickets, "feature_sets": feature_sets, "generated": datetime.now(UTC).isoformat()},
    indent=2
)

cm_config_json = json.dumps({
    "supabase_url": SUPABASE_URL,
    "supabase_publishable_key": SUPABASE_PUBLISHABLE_KEY,
    "project_name": PROJECT_NAME,
}, indent=2)

HTML = """<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="UTF-8">
<meta name="viewport" content="width=device-width, initial-scale=1.0">
<title>change-mate board</title>
<link rel="preconnect" href="https://fonts.googleapis.com">
<link href="https://fonts.googleapis.com/css2?family=Inter:wght@400;500;600&display=swap" rel="stylesheet">
<script src="https://cdn.jsdelivr.net/npm/@supabase/supabase-js@2/dist/umd/supabase.min.js"></script>
<style>
:root {
  --bg: #ffffff;
  --surface: #fafafa;
  --border: #e5e5e5;
  --text: #111111;
  --text2: #666666;
  --muted: #999999;
  --accent: #111111;
  --prog-fill: #111111;
  --prog-bg: #e5e5e5;
}
@media (prefers-color-scheme: dark) {
  :root {
    --bg: #111111;
    --surface: #1a1a1a;
    --border: #2a2a2a;
    --text: #f5f5f5;
    --text2: #888888;
    --muted: #555555;
    --accent: #f5f5f5;
    --prog-fill: #f5f5f5;
    --prog-bg: #2a2a2a;
  }
}
*, *::before, *::after { box-sizing: border-box; margin: 0; padding: 0; }
body {
  font-family: 'Inter', -apple-system, BlinkMacSystemFont, 'Segoe UI', sans-serif;
  font-size: 14px;
  line-height: 1.6;
  background: var(--bg);
  color: var(--text);
}
header {
  border-bottom: 1px solid var(--border);
  padding: 0 24px;
  height: 52px;
  display: flex;
  align-items: center;
  justify-content: space-between;
  position: sticky;
  top: 0;
  background: var(--bg);
  z-index: 10;
}
.logo { font-size: 14px; font-weight: 500; letter-spacing: -0.2px; }
.header-meta { font-size: 12px; color: var(--muted); }
main { max-width: 1280px; margin: 0 auto; padding: 24px; }
.tabs {
  display: flex;
  gap: 2px;
  background: var(--surface);
  border: 1px solid var(--border);
  border-radius: 8px;
  padding: 3px;
  width: fit-content;
  margin-bottom: 24px;
}
.tab {
  padding: 5px 14px;
  border-radius: 6px;
  border: none;
  background: none;
  cursor: pointer;
  font-size: 13px;
  font-weight: 500;
  color: var(--text2);
  font-family: inherit;
  transition: color 0.1s, background 0.1s;
}
.tab:hover { color: var(--text); }
.tab.active {
  background: var(--bg);
  color: var(--accent);
  box-shadow: 0 1px 3px rgba(0,0,0,0.08);
}
@media (prefers-color-scheme: dark) {
  .tab.active { box-shadow: 0 1px 3px rgba(0,0,0,0.4); }
}
.view { display: none; }
.view.active { display: block; animation: fadeIn 150ms ease; }
@keyframes fadeIn { from { opacity: 0; } to { opacity: 1; } }
.board { display: grid; grid-template-columns: repeat(4, 1fr); gap: 16px; }
.board.show-rejected { grid-template-columns: repeat(5, 1fr); }
.col-rejected { display: none; }
.board.show-rejected .col-rejected { display: block; }
.card.not-doing { opacity: 0.5; }
.card.not-doing .card-title { text-decoration: line-through; color: var(--text2); }
.btn-toggle-rejected {
  padding: 4px 10px;
  border-radius: 5px;
  border: 1px solid var(--border);
  cursor: pointer;
  font-size: 11px;
  font-weight: 500;
  font-family: inherit;
  background: none;
  color: var(--muted);
  margin-bottom: 16px;
  transition: color 100ms, border-color 100ms;
}
.btn-toggle-rejected:hover { color: var(--text2); border-color: var(--text2); }
.btn-toggle-rejected.active { color: var(--text); border-color: var(--text2); }
@media (max-width: 900px) { .board { grid-template-columns: 1fr 1fr; } .board.show-rejected { grid-template-columns: 1fr 1fr; } }
@media (max-width: 560px) { .board { grid-template-columns: 1fr; } .board.show-rejected { grid-template-columns: 1fr; } }
.col-head {
  display: flex;
  align-items: center;
  justify-content: space-between;
  padding-bottom: 10px;
  margin-bottom: 8px;
  border-bottom: 1px solid var(--border);
}
.col-name { font-size: 12px; font-weight: 500; color: var(--text2); text-transform: uppercase; letter-spacing: 0.5px; }
.col-count { font-size: 11px; color: var(--muted); font-weight: 500; }
.cards { display: flex; flex-direction: column; gap: 8px; }
.card {
  background: var(--surface);
  border: 1px solid var(--border);
  border-radius: 8px;
  padding: 12px 14px;
  cursor: pointer;
  transition: border-color 100ms;
}
.card:hover { border-color: var(--text2); }
.card-top { display: flex; align-items: flex-start; justify-content: space-between; gap: 8px; margin-bottom: 4px; }
.card-id {
  font-size: 11px;
  font-family: 'SFMono-Regular', Consolas, 'Liberation Mono', monospace;
  color: var(--muted);
}
.badges { display: flex; gap: 4px; flex-wrap: wrap; justify-content: flex-end; }
.badge { font-size: 10px; font-weight: 500; padding: 2px 6px; border-radius: 4px; }
.b-critical { background: #fee2e2; color: #991b1b; }
.b-high     { background: #ffedd5; color: #9a3412; }
.b-medium   { background: #fef9c3; color: #854d0e; }
.b-low      { background: #f1f5f9; color: #475569; }
.b-effort   { background: var(--bg); border: 1px solid var(--border); color: var(--muted); }
.card-title { font-size: 13px; font-weight: 500; color: var(--text); margin-bottom: 4px; }
.card-assignee { font-size: 11px; color: var(--muted); }
.card-fs {
  display: inline-block;
  font-size: 10px;
  font-weight: 500;
  color: var(--text2);
  background: var(--surface);
  border: 1px solid var(--border);
  border-radius: 10px;
  padding: 2px 8px;
  margin-bottom: 4px;
  white-space: nowrap;
}
.dl-val.pre { white-space: pre-line; }
.card-detail { max-height: 0; overflow: hidden; transition: max-height 200ms ease; }
.card.open .card-detail { max-height: 600px; }
.detail-inner {
  padding-top: 12px;
  margin-top: 12px;
  border-top: 1px solid var(--border);
  display: flex;
  flex-direction: column;
  gap: 10px;
}
.dl-label { font-size: 10px; font-weight: 600; text-transform: uppercase; letter-spacing: 0.5px; color: var(--muted); margin-bottom: 3px; }
.dl-val { font-size: 12px; color: var(--text2); }
.dl-list { list-style: none; font-size: 12px; color: var(--text2); }
.dl-list li { padding-left: 12px; position: relative; margin-bottom: 2px; }
.dl-list li::before { content: '\\00b7'; position: absolute; left: 0; color: var(--muted); }
.empty { font-size: 12px; color: var(--muted); padding: 8px 0; }
.feature-sets { display: flex; flex-direction: column; gap: 16px; }
.feature-set { border: 1px solid var(--border); border-radius: 8px; overflow: hidden; }
.feature-set-head {
  padding: 14px 18px;
  display: flex;
  align-items: flex-start;
  justify-content: space-between;
  gap: 12px;
  border-bottom: 1px solid var(--border);
}
.feature-set-name { font-size: 14px; font-weight: 500; margin-bottom: 2px; }
.feature-set-goal { font-size: 12px; color: var(--text2); }
.feature-set-status {
  font-size: 11px;
  font-weight: 500;
  padding: 3px 8px;
  border-radius: 12px;
  white-space: nowrap;
  background: var(--surface);
  border: 1px solid var(--border);
  color: var(--text2);
  text-transform: capitalize;
  flex-shrink: 0;
}
.feature-set-prog-row {
  padding: 10px 18px;
  display: flex;
  align-items: center;
  gap: 10px;
  border-bottom: 1px solid var(--border);
}
.prog-bar { flex: 1; height: 4px; background: var(--prog-bg); border-radius: 2px; overflow: hidden; }
.prog-fill { height: 100%; background: var(--prog-fill); border-radius: 2px; }
.prog-label { font-size: 11px; color: var(--muted); white-space: nowrap; }
.feature-set-cards { padding: 12px 14px; display: flex; flex-wrap: wrap; gap: 8px; }
.feature-set-cards .card { width: calc(25% - 6px); min-width: 180px; }
@media (max-width: 900px) { .feature-set-cards .card { width: calc(50% - 4px); } }
@media (max-width: 560px) { .feature-set-cards .card { width: 100%; } }
.header-right { display: flex; align-items: center; gap: 16px; }
.btn-new {
  padding: 5px 12px;
  border-radius: 6px;
  border: 1px solid var(--border);
  cursor: pointer;
  font-size: 12px;
  font-weight: 500;
  font-family: inherit;
  background: var(--surface);
  color: var(--text);
  white-space: nowrap;
  transition: border-color 100ms;
}
.btn-new:hover { border-color: var(--text2); }
.btn-github {
  padding: 5px 10px;
  border-radius: 6px;
  border: 1px solid var(--border);
  cursor: pointer;
  font-size: 12px;
  font-weight: 500;
  font-family: inherit;
  background: var(--surface);
  color: var(--text2);
  display: flex;
  align-items: center;
  gap: 5px;
  transition: border-color 100ms;
}
.btn-github:hover { border-color: var(--text2); }
.gh-dot { width: 6px; height: 6px; border-radius: 50%; background: var(--muted); flex-shrink: 0; transition: background 200ms; }
.gh-dot.connected { background: #22c55e; }
.settings-note { font-size: 11px; color: var(--muted); margin-top: 12px; line-height: 1.5; }
.settings-note code { font-family: 'SFMono-Regular', Consolas, monospace; background: var(--surface); padding: 1px 4px; border-radius: 3px; border: 1px solid var(--border); }
.modal-overlay {
  position: fixed;
  inset: 0;
  background: rgba(0,0,0,0.4);
  display: flex;
  align-items: center;
  justify-content: center;
  z-index: 50;
  animation: fadeIn 150ms ease;
}
@media (prefers-color-scheme: dark) {
  .modal-overlay { background: rgba(0,0,0,0.6); }
}
.modal {
  background: var(--bg);
  border: 1px solid var(--border);
  border-radius: 12px;
  padding: 24px;
  width: calc(100% - 32px);
  max-width: 480px;
  max-height: 90vh;
  overflow-y: auto;
  box-shadow: 0 20px 60px rgba(0,0,0,0.15);
}
@media (prefers-color-scheme: dark) { .modal { box-shadow: 0 20px 60px rgba(0,0,0,0.5); } }
.modal-title { font-size: 15px; font-weight: 500; margin-bottom: 20px; }
.field { margin-bottom: 14px; }
.field label { display: block; font-size: 11px; font-weight: 600; text-transform: uppercase; letter-spacing: 0.5px; color: var(--muted); margin-bottom: 5px; }
.field input, .field select, .field textarea {
  width: 100%;
  background: var(--surface);
  border: 1px solid var(--border);
  border-radius: 6px;
  padding: 7px 10px;
  font-size: 13px;
  color: var(--text);
  font-family: inherit;
  outline: none;
  transition: border-color 100ms;
}
.field select { cursor: pointer; }
.field input:focus, .field select:focus, .field textarea:focus { border-color: var(--text2); }
.field textarea { resize: vertical; min-height: 64px; line-height: 1.5; }
.field-row { display: grid; grid-template-columns: 1fr 1fr; gap: 12px; margin-bottom: 14px; }
.field-row .field { margin-bottom: 0; }
.modal-actions { display: flex; gap: 8px; justify-content: flex-end; margin-top: 20px; padding-top: 16px; border-top: 1px solid var(--border); }
.btn {
  padding: 7px 16px;
  border-radius: 6px;
  border: 1px solid var(--border);
  cursor: pointer;
  font-size: 13px;
  font-weight: 500;
  font-family: inherit;
  background: var(--surface);
  color: var(--text2);
  transition: border-color 100ms;
}
.btn:hover { border-color: var(--text2); }
.btn-primary { background: var(--text); color: var(--bg); border-color: var(--text); }
.btn-primary:hover { opacity: 0.85; }
#toast {
  position: fixed;
  bottom: 24px;
  left: 50%;
  transform: translateX(-50%) translateY(8px);
  background: var(--text);
  color: var(--bg);
  padding: 10px 18px;
  border-radius: 8px;
  font-size: 12px;
  max-width: 560px;
  width: calc(100% - 48px);
  text-align: center;
  opacity: 0;
  transition: opacity 200ms, transform 200ms;
  pointer-events: none;
  z-index: 100;
}
#toast.show { opacity: 1; transform: translateX(-50%) translateY(0); }
@keyframes cm-pulse {
  0%   { background: var(--surface); }
  30%  { background: #fef9c3; }
  100% { background: var(--surface); }
}
@keyframes cm-fadein {
  from { opacity: 0; transform: translateY(-8px); }
  to   { opacity: 1; transform: translateY(0); }
}
.cm-moving { animation: cm-pulse 600ms ease; }
.cm-new { animation: cm-fadein 300ms ease; }
</style>
</head>
<body>
<header>
  <div style="display:flex;align-items:center;gap:10px;">
    <span class="logo">change-mate</span>
    <span id="cm-live-indicator" style="display:none; align-items:center; gap:5px; font-size:12px; color:#666;">
      <span style="width:7px;height:7px;border-radius:50%;background:#22c55e;display:inline-block;"></span>
      live
    </span>
  </div>
  <div class="header-right">
    <span class="header-meta" id="gen-time"></span>
    <button class="btn-github" onclick="openSettings()">
      <span class="gh-dot" id="gh-dot"></span>GitHub
    </button>
    <button class="btn-new" onclick="openModal()">+ Add story</button>
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

function esc(s) {
  return String(s || '').replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;');
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

function cardHTML(t, isRejected) {
  var rejClass = (isRejected || t.status === 'not-doing') ? ' not-doing' : '';
  var fsChip = t.feature_set ? '<div class="card-fs">' + esc(t.feature_set) + '</div>' : '';
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

  var detail = goal + why + dw + desired + success + failure + tests + notes + rejection;
  return '<div class="card' + rejClass + '" onclick="toggleCard(this)">'
    + '<div class="card-top">'
    + '<span class="card-id">' + esc(t.id) + '</span>'
    + '<div class="badges">' + priorityBadge(t.priority) + (t.effort ? '<span class="badge b-effort">' + esc(t.effort) + '</span>' : '') + '</div>'
    + '</div>'
    + '<div class="card-title">' + esc(t.title || t.id) + '</div>'
    + fsChip
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
      + '<div class="feature-set-cards">' + (list.length ? list.map(cardHTML).join('') : '<div class="empty">No tickets</div>') + '</div>'
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

function getNextId() {
  var nums = D.tickets.map(function(t) {
    var m = (t.id || '').match(/^CM-(\\d+)$/);
    return m ? parseInt(m[1], 10) : 0;
  });
  var max = nums.length ? Math.max.apply(null, nums) : 0;
  var n = String(max + 1);
  while (n.length < 3) n = '0' + n;
  return 'CM-' + n;
}

async function createStory() {
  var title = document.getElementById('f-title').value.trim();
  if (!title) { document.getElementById('f-title').focus(); return; }
  var id       = getNextId();
  var ts       = Math.floor(Date.now() / 1000);
  var filename = id + '-' + ts + '.md';
  var priority = document.getElementById('f-priority').value;
  var effort   = document.getElementById('f-effort').value;
  var assigned = document.getElementById('f-assigned').value.trim();
  var goal     = document.getElementById('f-goal').value.trim();
  var why      = document.getElementById('f-why').value.trim();
  var doneRaw  = document.getElementById('f-done').value.trim();
  var notes    = document.getElementById('f-notes').value.trim();
  var fsId     = document.getElementById('f-featureset').value;
  var lines = ['# [' + id + '] ' + title, ''];
  lines.push('- **Status**: open');
  if (priority) lines.push('- **Priority**: ' + priority);
  if (effort)   lines.push('- **Effort**: ' + effort);
  lines.push('- **Assigned to**: ' + (assigned || ''));
  lines.push('- **Started**: ');
  lines.push('- **Completed**: ');
  lines.push('', '## Goal', goal || '', '', '## Why', why || '', '', '## Done when');
  if (doneRaw) {
    doneRaw.split('\\n').forEach(function(l) { var t = l.trim(); if (t) lines.push('- ' + t); });
  }
  lines.push('', '## Notes', notes || '', '');
  var content = lines.join('\\n');
  var fsNote = '';
  if (fsId) {
    var matchedFs = D.feature_sets.filter(function(fs) { return fs.id === fsId; })[0];
    if (matchedFs) fsNote = '\\nAlso add ' + id + ' to the tickets list in ' + fsId + '.md';
  }
  closeModal();
  var token = localStorage.getItem('cm_github_token');
  var repo  = localStorage.getItem('cm_github_repo') || DEFAULT_REPO;
  if (token && repo) {
    try {
      await createViaGitHub('change-mate/backlog/' + filename, content, id + ': add to backlog', token, repo);
      showToast(filename + ' saved to backlog.' + fsNote);
    } catch(e) {
      showToast('GitHub error: ' + e.message);
    }
  } else {
    var a = document.createElement('a');
    a.href = URL.createObjectURL(new Blob([content], {type: 'text/plain'}));
    a.download = filename;
    a.click();
    URL.revokeObjectURL(a.href);
    showToast(filename + ' downloaded — move to change-mate/backlog/ and run build.sh. Configure GitHub to save directly.' + fsNote);
  }
}

async function createViaGitHub(path, content, message, token, repo) {
  var encoded = btoa(unescape(encodeURIComponent(content)));
  var res = await fetch('https://api.github.com/repos/' + repo + '/contents/' + path, {
    method: 'PUT',
    headers: {
      'Authorization': 'token ' + token,
      'Content-Type': 'application/json',
      'Accept': 'application/vnd.github.v3+json'
    },
    body: JSON.stringify({message: message, content: encoded})
  });
  if (!res.ok) {
    var err = await res.json().catch(function() { return {}; });
    throw new Error(err.message || ('HTTP ' + res.status));
  }
  return res.json();
}

var _toastTimer;
function showToast(msg) {
  var el = document.getElementById('toast');
  el.textContent = msg;
  el.classList.add('show');
  clearTimeout(_toastTimer);
  _toastTimer = setTimeout(function() { el.classList.remove('show'); }, 5000);
}

function openSettings() {
  document.getElementById('s-token').value = localStorage.getItem('cm_github_token') || '';
  document.getElementById('s-repo').value = localStorage.getItem('cm_github_repo') || DEFAULT_REPO;
  document.getElementById('settings-modal').style.display = 'flex';
  setTimeout(function() { document.getElementById('s-token').focus(); }, 50);
}

function closeSettings() {
  document.getElementById('settings-modal').style.display = 'none';
}

function saveSettings() {
  var token = document.getElementById('s-token').value.trim();
  var repo  = document.getElementById('s-repo').value.trim();
  if (token) localStorage.setItem('cm_github_token', token);
  else localStorage.removeItem('cm_github_token');
  if (repo) localStorage.setItem('cm_github_repo', repo);
  else localStorage.removeItem('cm_github_repo');
  checkGitHubStatus();
  closeSettings();
  showToast('GitHub settings saved.');
}

function checkGitHubStatus() {
  var dot = document.getElementById('gh-dot');
  if (!dot) return;
  if (localStorage.getItem('cm_github_token')) dot.classList.add('connected');
  else dot.classList.remove('connected');
}

document.addEventListener('keydown', function(e) {
  if (e.key === 'Escape') { closeModal(); closeSettings(); }
});

checkGitHubStatus();
</script>
<script id="cm-config" type="application/json">PLACEHOLDER_CONFIG</script>
<script>
(function() {
  var cfg = JSON.parse(document.getElementById('cm-config').textContent);
  if (!cfg.supabase_url || !cfg.supabase_publishable_key) return;

  var client = supabase.createClient(cfg.supabase_url, cfg.supabase_publishable_key);
  var channel = client.channel('change-mate');

  channel.on('broadcast', { event: 'ticket_updated' }, function(e) {
    handleTicketUpdate(e.payload);
  });

  channel.subscribe(function(status) {
    if (status === 'SUBSCRIBED') {
      document.getElementById('cm-live-indicator').style.display = 'flex';
    }
  });

  function handleTicketUpdate(data) {
    var colMap = {
      'backlog': 'c-backlog', 'open': 'c-backlog',
      'in-progress': 'c-inprogress', 'done': 'c-done',
      'blocked': 'c-blocked', 'not-doing': 'c-notdoing'
    };
    var targetColId = colMap[data.to_status];
    if (!targetColId) return;
    var targetCol = document.getElementById(targetColId);
    if (!targetCol) return;

    var existing = null;
    document.querySelectorAll('#view-board .card').forEach(function(card) {
      var el = card.querySelector('.card-id');
      if (el && el.textContent.trim() === data.ticket_id) existing = card;
    });

    if (existing) {
      existing.classList.add('cm-moving');
      existing.parentNode.removeChild(existing);
      targetCol.insertBefore(existing, targetCol.firstChild);
      setTimeout(function() { existing.classList.remove('cm-moving'); }, 600);
    } else {
      var card = document.createElement('div');
      card.className = 'card cm-new';
      card.onclick = function() { toggleCard(this); };
      card.innerHTML = '<div class="card-top"><span class="card-id">' + esc(data.ticket_id) + '</span></div>'
        + '<div class="card-title">' + esc(data.title || data.ticket_id) + '</div>';
      targetCol.insertBefore(card, targetCol.firstChild);
    }

    ['c-backlog','c-inprogress','c-done','c-blocked','c-notdoing'].forEach(function(id) {
      var col = document.getElementById(id);
      var cnt = document.getElementById(id.replace('c-', 'n-'));
      if (col && cnt) cnt.textContent = col.querySelectorAll('.card').length;
    });
  }
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
<div id="settings-modal" class="modal-overlay" style="display:none" onclick="if(event.target===this)closeSettings()">
  <div class="modal">
    <div class="modal-title">GitHub settings</div>
    <div class="field">
      <label>Personal access token</label>
      <input type="password" id="s-token" placeholder="ghp_...">
    </div>
    <div class="field">
      <label>Repository</label>
      <input type="text" id="s-repo" placeholder="owner/repo">
    </div>
    <p class="settings-note">Token needs <code>repo</code> scope. Stored in your browser only — never sent anywhere except GitHub's API.</p>
    <div class="modal-actions">
      <button class="btn" onclick="closeSettings()">Cancel</button>
      <button class="btn btn-primary" onclick="saveSettings()">Save</button>
    </div>
  </div>
</div>
<div id="toast"></div>
</body>
</html>"""

output = (HTML
    .replace("PLACEHOLDER_JSON", data_json)
    .replace("PLACEHOLDER_REPO", json.dumps(GITHUB_REPO))
    .replace("PLACEHOLDER_CONFIG", cm_config_json))
Path("change-mate-board.html").write_text(output, encoding="utf-8")
print("change-mate-board.html updated")
PYEOF
