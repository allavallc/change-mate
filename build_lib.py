import re


def parse_ticket(path, default_status):
    text = path.read_text(encoding="utf-8")
    lines = text.splitlines()
    stem = path.stem
    stem_m = re.match(r"^(CM-\d+)(?:-\d+)?$", stem)
    t = {
        "id": stem_m.group(1) if stem_m else stem, "title": "", "status": default_status,
        "priority": "", "effort": "", "assigned_to": "",
        "started": "", "completed": "", "goal": "",
        "why": "", "done_when": [], "notes": "",
        "rejected_by": "", "rejected": "", "rejection_reason": ""
    }
    if lines:
        m = re.match(r"^#\s+\[([^\]]+)\]\s+(.+)$", lines[0])
        if m:
            t["id"] = m.group(1)
            t["title"] = m.group(2).strip()
    for line in lines:
        m = re.match(r"^-\s+\*\*([^*]+)\*\*:\s*(.*)", line)
        if m:
            k = m.group(1).strip().lower().replace(" ", "_")
            v = m.group(2).strip()
            if k in ("priority", "effort", "assigned_to", "started", "completed", "rejected_by", "rejected", "rejection_reason") and v:
                t[k] = v
            elif k == "status" and v:
                t["status"] = v
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


def parse_feature_set(path):
    text = path.read_text(encoding="utf-8")
    lines = text.splitlines()
    s = {"id": path.stem, "name": path.stem, "goal": "", "status": "planned", "tickets": []}
    if lines:
        m = re.match(r"^#\s+(.+)$", lines[0])
        if m:
            s["name"] = m.group(1).strip()
    for line in lines:
        m = re.match(r"^-\s+\*\*([^*]+)\*\*:\s*(.*)", line)
        if m:
            k = m.group(1).strip().lower()
            v = m.group(2).strip()
            if k == "status":
                s["status"] = v
            elif k == "goal":
                s["goal"] = v
            elif k == "tickets":
                s["tickets"] = [x.strip() for x in v.split(",") if x.strip()]
    return s
