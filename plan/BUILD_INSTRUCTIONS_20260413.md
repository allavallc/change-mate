# change-mate build instructions
# Version: 20260413

---

## What this version adds

- Real-time ticket movement visible to humans in the browser
- Agents publish events when they claim or complete a ticket
- The board subscribes to the same channel and animates ticket cards live
- Powered by Supabase Realtime — free tier, no database needed

---

## Supabase setup (one-time, done by the repo owner)

Tell the user to do the following before running any code:

1. Go to https://supabase.com and create a free account
2. Create a new project — name it "change-mate" or anything you like
3. Once the project is ready, go to Project Settings → API
4. Copy two values:
   - **Project URL** — looks like `https://xxxxxxxxxxxx.supabase.co`
   - **Publishable key** — starts with `sb_publishable_...`
5. Open `change-mate-config.json` in the repo and add these values:

```json
{
  "gist_id": "",
  "project_name": "my project",
  "supabase_url": "https://xxxxxxxxxxxx.supabase.co",
  "supabase_publishable_key": "your-anon-key-here"
}
```

6. No database tables are needed — only Supabase Realtime is used
7. In the Supabase dashboard go to Realtime → and confirm Realtime is enabled for the project

The publishable key is safe to commit — it is a public read/broadcast key with no write access to any database.

---

## Step 1 — Update change-mate-config.json

Ensure the file at the repo root has this structure:

```json
{
  "gist_id": "",
  "project_name": "my project",
  "supabase_url": "",
  "supabase_publishable_key": ""
}
```

---

## Step 2 — Update CHANGEMATE.md

Add the following rules to the existing `CHANGEMATE.md` under a new section called "Real-time sync":

```
## Real-time sync

change-mate uses Supabase Realtime to broadcast ticket events so that
other agents and the human board see changes instantly.

### When to broadcast

Broadcast a Supabase Realtime event in these situations:

1. When claiming a ticket (moving to in-progress)
2. When completing a ticket (moving to done)
3. When blocking a ticket (moving to blocked)
4. When creating a new ticket

### How to broadcast

Read supabase_url and supabase_publishable_key from change-mate-config.json.
Then send a POST request to the Supabase Realtime broadcast endpoint:

  POST {supabase_url}/realtime/v1/api/broadcast
  Headers:
    Content-Type: application/json
    apikey: {supabase_publishable_key}
    Authorization: Bearer {supabase_publishable_key}
  Body:
    {
      "messages": [{
        "topic": "change-mate",
        "event": "ticket_updated",
        "payload": {
          "ticket_id": "CM-004",
          "title": "Add user authentication",
          "from_status": "backlog",
          "to_status": "in-progress",
          "assigned_to": "alex",
          "timestamp": "<ISO timestamp>"
        }
      }]
    }

If supabase_url or supabase_publishable_key are missing from change-mate-config.json,
skip the broadcast silently and continue as normal.

### Do not wait for a response

Fire the broadcast and move on. Do not block work on a failed broadcast.
```

---

## Step 3 — Update build.sh

`build.sh` must now inject the Supabase credentials into the board HTML so the
board can subscribe to the live channel.

After generating the JSON data blob, also inject a second script tag:

```html
<script id="cm-config" type="application/json">
{
  "supabase_url": "...",
  "supabase_publishable_key": "...",
  "project_name": "..."
}
</script>
```

Read these values from `change-mate-config.json` when building. If the values
are empty, inject empty strings — the board will fall back to static mode.

---

## Step 4 — Update change-mate-board.html

The board must now:

1. Load the Supabase JS client from CDN
2. Subscribe to the "change-mate" Realtime channel on page load
3. Animate ticket cards when events arrive

### CDN import (add to head)

```html
<script src="https://cdn.jsdelivr.net/npm/@supabase/supabase-js@2/dist/umd/supabase.min.js"></script>
```

### On page load — subscribe to channel

```javascript
const config = JSON.parse(document.getElementById('cm-config').textContent);

if (config.supabase_url && config.supabase_publishable_key) {
  const client = supabase.createClient(config.supabase_url, config.supabase_publishable_key);

  const channel = client.channel('change-mate');

  channel.on('broadcast', { event: 'ticket_updated' }, (payload) => {
    handleTicketUpdate(payload.payload);
  });

  channel.subscribe();
}
```

### handleTicketUpdate function

When an event arrives:

1. Find the ticket card in the DOM by ticket_id
2. If found — animate it moving to the new column:
   - Add a CSS class `cm-moving` to the card (triggers a highlight pulse animation)
   - Remove the card from its current column
   - Prepend it to the top of the new column
   - Remove `cm-moving` after 600ms
3. If not found — the ticket is new. Add a new card to the top of the correct column with a `cm-new` CSS animation (fade in from top)
4. Update the column ticket counts

### CSS animations to add

```css
@keyframes cm-pulse {
  0%   { background: var(--card-bg); }
  30%  { background: #fef9c3; }
  100% { background: var(--card-bg); }
}

@keyframes cm-fadein {
  from { opacity: 0; transform: translateY(-8px); }
  to   { opacity: 1; transform: translateY(0); }
}

.cm-moving {
  animation: cm-pulse 600ms ease;
}

.cm-new {
  animation: cm-fadein 300ms ease;
}
```

### Live indicator

Add a small live indicator in the header next to the project name:

- When Supabase is connected: a small green dot + "live" in muted text
- When not connected or no credentials: nothing shown (static mode is silent)

```html
<span id="cm-live-indicator" style="display:none; align-items:center; gap:5px; font-size:12px; color:#666;">
  <span style="width:7px;height:7px;border-radius:50%;background:#22c55e;display:inline-block;"></span>
  live
</span>
```

Show it once the channel subscribes successfully:
```javascript
channel.subscribe((status) => {
  if (status === 'SUBSCRIBED') {
    document.getElementById('cm-live-indicator').style.display = 'flex';
  }
});
```

---

## Step 5 — Update the GitHub Action

The GitHub Action that rebuilds the board needs access to the Supabase credentials
so `build.sh` can inject them into the HTML.

Update `.github/workflows/build-board.yml` to pass the credentials as environment
variables, sourced from GitHub Actions secrets:

```yaml
- name: Build board
  env:
    SUPABASE_URL: ${{ secrets.SUPABASE_URL }}
    SUPABASE_PUBLISHABLE_KEY: ${{ secrets.SUPABASE_PUBLISHABLE_KEY }}
  run: bash build.sh
```

And update `build.sh` to read from environment variables first, falling back to
`change-mate-config.json`:

```bash
SUPABASE_URL=${SUPABASE_URL:-$(node -e "const c=require('./change-mate-config.json');console.log(c.supabase_url||'')")}
SUPABASE_PUBLISHABLE_KEY=${SUPABASE_PUBLISHABLE_KEY:-$(node -e "const c=require('./change-mate-config.json');console.log(c.supabase_publishable_key||'')")}
```

Tell the user to add SUPABASE_URL and SUPABASE_PUBLISHABLE_KEY as GitHub Actions secrets:
- Go to the repo on GitHub
- Settings → Secrets and variables → Actions
- Add SUPABASE_URL and SUPABASE_PUBLISHABLE_KEY

---

## Step 6 — Verify

1. Run `bash build.sh` — confirm `change-mate-board.html` is generated with the config injected
2. Open `change-mate-board.html` in a browser — confirm the green "live" dot appears in the header
3. In a Claude Code session, claim a ticket — confirm the card moves in the open browser tab in real time
4. Open the board in two browser tabs — confirm both update simultaneously

---

## Fallback behaviour

If Supabase credentials are missing or the connection fails:
- The board loads and works as a normal static board
- No error is shown to the user
- The live indicator is simply not displayed
- Agents skip the broadcast silently

change-mate must always work without Supabase. Real-time is an enhancement, not a requirement.

---

## What NOT to do

- Do not create any Supabase database tables — only Realtime broadcast is used
- Do not store ticket content in Supabase — the repo is always the source of truth
- Do not block agent work on a failed broadcast
- Do not commit the anon key as a hardcoded string in any JS — always inject via build.sh
- Do not use Supabase presence or postgres changes — broadcast only
