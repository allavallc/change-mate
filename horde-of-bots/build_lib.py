import re


DEFAULT_PREFIX = "CM"


def _id_re(prefix):
    return re.compile(rf"^{re.escape(prefix)}-\d+$")


def _stem_re(prefix):
    return re.compile(rf"^({re.escape(prefix)}-\d+)(?:-\d+)?$")


def _list_id_re(prefix):
    return re.compile(rf"^-\s+({re.escape(prefix)}-\d+)")


def _parse_id_list(value, prefix=DEFAULT_PREFIX):
    """Split a comma-separated ticket-ID list. Strip whitespace, drop malformed entries, dedupe."""
    if not value:
        return []
    id_re = _id_re(prefix)
    out = []
    seen = set()
    for chunk in value.split(","):
        s = chunk.strip()
        if id_re.match(s) and s not in seen:
            out.append(s)
            seen.add(s)
    return out


def parse_ticket(path, default_status, prefix=DEFAULT_PREFIX):
    text = path.read_text(encoding="utf-8")
    lines = text.splitlines()
    stem = path.stem
    stem_m = _stem_re(prefix).match(stem)
    t = {
        "id": stem_m.group(1) if stem_m else stem,
        "title": "",
        "status": default_status,
        "priority": "",
        "effort": "",
        "feature_set": "",
        "related": [],
        "blocks": [],
        "blocked_by": [],
        "split_from": [],
        "assigned_to": "",
        "started": "",
        "completed": "",
        "goal": "",
        "why": "",
        "done_when": [],
        "desired_output": "",
        "success_signals": "",
        "failure_signals": "",
        "tests": "",
        "notes": "",
        "rejected_by": "",
        "rejected": "",
        "rejection_reason": "",
    }
    if lines:
        m = re.match(r"^#\s+\[([^\]]+)\]\s+(.+)$", lines[0])
        if m:
            t["id"] = m.group(1)
            t["title"] = m.group(2).strip()

    bullet_keys = (
        "priority", "effort", "feature_set", "assigned_to",
        "started", "completed", "rejected_by", "rejected", "rejection_reason",
    )
    id_list_keys = ("related", "blocks", "blocked_by", "split_from")
    for line in lines:
        m = re.match(r"^-\s+\*\*([^*]+)\*\*:\s*(.*)", line)
        if m:
            k = m.group(1).strip().lower().replace(" ", "_")
            v = m.group(2).strip()
            if k in bullet_keys and v:
                t[k] = v
            elif k == "status" and v:
                t["status"] = v
            elif k in id_list_keys:
                t[k] = _parse_id_list(v, prefix)

    section, buf = None, []

    def flush():
        if not section:
            return
        block = "\n".join(buf).strip()
        if section == "goal":
            t["goal"] = block
        elif section == "why":
            t["why"] = block
        elif section == "done_when":
            t["done_when"] = [l.lstrip("- ").strip() for l in buf if l.strip().startswith("-")]
        elif section == "desired_output":
            t["desired_output"] = block
        elif section == "success_signals":
            t["success_signals"] = block
        elif section == "failure_signals":
            t["failure_signals"] = block
        elif section == "tests":
            t["tests"] = block
        elif section == "notes":
            t["notes"] = block

    for line in lines[1:]:
        if line.startswith("## "):
            flush()
            section = line[3:].strip().lower().replace(" ", "_")
            buf = []
        else:
            buf.append(line)
    flush()
    return t


def parse_feature_set(path, prefix=DEFAULT_PREFIX):
    text = path.read_text(encoding="utf-8")
    lines = text.splitlines()
    s = {
        "id": path.stem,
        "name": path.stem,
        "goal": "",
        "rationale": "",
        "status": "planned",
        "tickets": [],
    }
    if lines:
        m = re.match(r"^#\s+(.+)$", lines[0])
        if m:
            s["name"] = m.group(1).strip()

    for line in lines:
        m = re.match(r"^-\s+\*\*([^*]+)\*\*:\s*(.*)", line)
        if m:
            k = m.group(1).strip().lower()
            v = m.group(2).strip()
            if k == "status" and v:
                s["status"] = v
            elif k == "goal" and v:
                s["goal"] = v
            elif k == "tickets" and v:
                s["tickets"] = [x.strip() for x in v.split(",") if x.strip()]

    section, buf = None, []
    list_re = _list_id_re(prefix)

    def flush():
        if not section:
            return
        block = "\n".join(buf).strip()
        if section == "goal" and block:
            s["goal"] = block
        elif section == "rationale" and block:
            s["rationale"] = block
        elif section == "status" and block:
            s["status"] = block
        elif section == "tickets":
            ids = [
                list_re.match(l.strip()).group(1)
                for l in buf
                if list_re.match(l.strip())
            ]
            if ids:
                s["tickets"] = ids

    for line in lines[1:]:
        if line.startswith("## "):
            flush()
            section = line[3:].strip().lower()
            buf = []
        else:
            buf.append(line)
    flush()

    return s
