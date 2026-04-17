# Setting up change-mate

Two levels. Pick the one you need.

| Level | What you get | Time |
|---|---|---|
| **Basic** (step 1) | A board you can look at. No creating tickets from the browser. | 2 minutes |
| **Full** (steps 1–3) | Live board with real-time updates. Create tickets from the browser. See which agents are working on what. | 15 minutes |

---

## Step 1 — Install change-mate

From an agent session (any AI agent or bot that can run shell commands), say:

```
I want to use change-mate. Set it up from https://github.com/allavallc/change-mate
```

Or run it manually:

```bash
curl -fsSL https://raw.githubusercontent.com/allavallc/change-mate/main/setup.sh | bash
```

Save it to your repo:

```bash
git add change-mate/ CHANGEMATE.md CLAUDE.md
git commit -m "add change-mate"
git push
```

Open `change-mate-board.html` to see your board:

- **On your computer:** double-click the file. It opens in your browser.
- **Shared link:** GitHub repo → **Settings → Pages → Build from branch → `main` / root → Save**. Your board is at `https://your-username.github.io/your-repo/change-mate-board.html`.

**Board visibility follows repo visibility.** Public repo = public board. Private repo = private board (requires GitHub Pro for private Pages).

If you just want to look at the board, **you're done.** Stop here.

---

## Step 2 — Connect to Supabase (live updates)

This gives the board a database for real-time updates — you'll see tickets appear and move as agents work on them.

### 2.1 — Create a Supabase project

1. Go to **[supabase.com/dashboard](https://supabase.com/dashboard)** and sign in (GitHub login works).
2. Click **New project**.
3. Name it anything (e.g. `change-mate`). Generate a database password and save it. Pick your region.
4. Click **Create new project**. Wait ~2 minutes.

### 2.2 — Copy your connection details

1. Click the **gear icon** (bottom-left) → **API**.
2. Copy these two values somewhere:
   - **Project URL** — `https://abcdefg.supabase.co`
   - **anon public key** — long string starting with `sb_publishable_` or `eyJ`
3. Scroll to **Data API**. If there's an **Enable Data API** toggle, turn it ON, make sure `public` is in the dropdown, Save.

### 2.3 — Set up the database

1. In the sidebar, click **SQL Editor** → **New query**.
2. Open `supabase/migrations/0001_initial.sql` from this repo. Select all, copy, paste into the editor. Click **Run**.
3. Do the same for `supabase/migrations/0002_ticket_id_sequence.sql`.
4. Do the same for `supabase/migrations/0003_locks_select_policy.sql`.

All three should say **Success. No rows returned.**

### 2.4 — Enable Realtime on the locks table

1. In the sidebar, click **Database → Replication** (or **Publications**).
2. Click on **supabase_realtime**.
3. Toggle **locks** ON.

This lets the board show which agents are actively working on tickets.

### 2.5 — Connect change-mate to Supabase

Open `change-mate-config.json` and fill in your values:

```json
{
  "gist_id": "",
  "project_name": "my project",
  "supabase_url": "https://abcdefg.supabase.co",
  "supabase_publishable_key": "your-anon-key-here"
}
```

If you use GitHub Actions, also add repo secrets: `SUPABASE_URL` and `SUPABASE_PUBLISHABLE_KEY` (repo → Settings → Secrets → Actions).

### 2.6 — Verify

```bash
py scripts/verify_supabase.py
```

You should see three `[PASS]` lines. If not, re-run the SQL migrations.

---

## Step 3 — Enable "Add Story" (create tickets from the board)

### 3.1 — Install the Supabase CLI and deploy

```bash
npm install -g supabase
supabase login
supabase link --project-ref abcdefg
```

Replace `abcdefg` with your project ref (the part before `.supabase.co` in your URL).

### 3.2 — Create a GitHub token for the server

This token lets the server commit ticket files to your repo. Create it once.

1. Go to **[github.com/settings/tokens?type=beta](https://github.com/settings/tokens?type=beta)**.
2. Click **Generate new token**.
3. **Token name:** `change-mate`
4. **Repository access:** Only select repositories → pick this repo.
5. **Permissions → Repository permissions → Contents:** Read and write.
6. Click **Generate token**. Copy it. Save it in your password manager.

### 3.3 — Deploy

```bash
supabase secrets set GITHUB_PAT=your-token-here
supabase secrets set GITHUB_OWNER=your-github-username
supabase secrets set GITHUB_REPO=your-repo-name
supabase functions deploy cm-write --no-verify-jwt
```

### 3.4 — Try it

1. Open the board in your browser.
2. Click **+ Add story**.
3. It will ask for your name and a GitHub token. This is YOUR personal token (not the server one from 3.2 — create a second one the same way, or reuse if you want).
4. Fill in the form. Click **Create story**.
5. The ticket should appear in the backlog.

**This setup is one-time.** The board remembers your name and token.

---

## Adding other people

1. Add them as a **GitHub collaborator** on your repo (repo → Settings → Collaborators → Add people).
2. They create their own GitHub token (same steps as 3.2 — takes 2 minutes).
3. They open the board, click Add Story, enter their name and token once. Done.

**Removing someone:** Remove them as a GitHub collaborator. Their token stops working immediately.

---

## Troubleshooting

| What you see | What to do |
|---|---|
| Board loads but no live indicator | Check `supabase_url` and `supabase_publishable_key` in `change-mate-config.json` |
| Add Story says "Network error" | The cm-write function isn't deployed. Do step 3.3. |
| Add Story says "Access denied" | Your GitHub token doesn't have push access to this repo. Create a new one (step 3.2). |
| `PGRST002` error | Data API is off. Supabase → Settings → API → Data API → Enable → Save. |
| Everything stopped working | Free Supabase projects pause after ~1 week. Go to dashboard → click **Restore**. |

---

## For developers

```bash
py -m pytest -v                    # run all tests
bash build.sh                      # rebuild board locally (don't commit the output)
deno test --allow-env supabase/functions/cm-write/   # run Edge Function tests
```

Future migrations go in `supabase/migrations/NNNN_*.sql`. Apply them in the SQL editor. They're all idempotent.
