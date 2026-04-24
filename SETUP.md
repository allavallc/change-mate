# Setting up change-mate

Two paths. Pick the one that fits.

## Are you solo or a team?

**Solo** — just you, using change-mate in your own repo.
- You view the board in your browser.
- You add or move tickets by editing markdown files in the repo and pushing.
- No accounts, no tokens. ~2 minutes.
- → Jump to **[Solo path](#solo-path)**.

**Team** — multiple people or agents working together.
- Everyone sees the board update in real-time.
- Anyone can click "Add story" in the browser and create tickets without touching the command line.
- Live locks prevent two people from grabbing the same ticket at the same time.
- One person does a ~15-minute setup once. Everyone else just opens the board.
- → Jump to **[Team path](#team-path)**.

You can start solo and upgrade to team later. Your tickets stay where they are — nothing to migrate.

---

# Solo path

Everything you need to view and manage a board by yourself.

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
git add change-mate/ CLAUDE.md
git commit -m "add change-mate"
git push
```

## Step 2 — Open the board

- **On your computer:** double-click `change-mate/board.html`. It opens in your browser.
- **Shared link:** GitHub repo → **Settings → Pages → Build from branch → `main` / root → Save**. Your board is at `https://your-username.github.io/your-repo/change-mate/board.html`.

**Board visibility follows repo visibility.** Public repo = public board. Private repo = private board (requires GitHub Pro for private Pages).

## Step 3 — Add or move tickets

You edit markdown files in the repo.

- **New ticket:** create a file in `change-mate/backlog/` named `CM-XXX-<timestamp>.md`. Use any existing ticket as a template.
- **Start work:** move the file to `change-mate/in-progress/`.
- **Finish:** move the file to `change-mate/done/`.

Commit and push. GitHub rebuilds the board automatically on every push to `main`.

**That's it.** You're done.

Want the "Add story" button to work from the browser, or live updates as tickets move? That's the [Team path](#team-path) — you can upgrade anytime.

---

# Team path

Everything solo gives you, plus: real-time board updates, "Add story" button in the browser, and live locks so two people can't grab the same ticket.

**Do the Solo path first** — you need change-mate installed in your repo before the team features can connect to it.

One person does the three steps below. Everyone else just opens the board and follows [Adding people to the team](#adding-people-to-the-team).

## Step 1 — Create a Supabase project

1. Go to **[supabase.com/dashboard](https://supabase.com/dashboard)** and sign in (GitHub login works).
2. Click **New project**.
3. Name it anything (e.g. `change-mate`). Generate a database password and save it. Pick your region.
4. Click **Create new project**. Wait ~2 minutes.

### Copy your connection details

1. Click the **gear icon** (bottom-left) → **API**.
2. Copy these two values somewhere:
   - **Project URL** — `https://abcdefg.supabase.co`
   - **anon public key** — long string starting with `sb_publishable_` or `eyJ`
3. Scroll to **Data API**. If there's an **Enable Data API** toggle, turn it ON, make sure `public` is in the dropdown, Save.

### Set up the database

1. In the sidebar, click **SQL Editor** → **New query**.
2. Open `supabase/migrations/0001_initial.sql` from this repo. Select all, copy, paste into the editor. Click **Run**.
3. Do the same for `supabase/migrations/0002_ticket_id_sequence.sql`.
4. Do the same for `supabase/migrations/0003_locks_select_policy.sql`.

All three should say **Success. No rows returned.**

### Enable Realtime on the locks table

1. In the sidebar, click **Database → Replication** (or **Publications**).
2. Click on **supabase_realtime**.
3. Toggle **locks** ON.

This lets the board show which agents are actively working on tickets.

### Connect change-mate to Supabase

Open `change-mate/config.json` and fill in your values:

```json
{
  "gist_id": "",
  "project_name": "my project",
  "supabase_url": "https://abcdefg.supabase.co",
  "supabase_publishable_key": "your-anon-key-here"
}
```

If you use GitHub Actions, also add repo secrets: `SUPABASE_URL` and `SUPABASE_PUBLISHABLE_KEY` (repo → Settings → Secrets → Actions).

### Verify

```bash
py scripts/verify_supabase.py
```

You should see three `[PASS]` lines. If not, re-run the SQL migrations.

## Step 2 — Enable "Add story" from the browser

### Install the Supabase CLI and link your project

```bash
npm install -g supabase
supabase login
supabase link --project-ref abcdefg
```

Replace `abcdefg` with your project ref (the part before `.supabase.co` in your URL).

### Create a GitHub token for the server

This token lets the server commit ticket files to your repo. Create it once.

1. Go to **[github.com/settings/tokens?type=beta](https://github.com/settings/tokens?type=beta)**.
2. Click **Generate new token**.
3. **Token name:** `change-mate`
4. **Repository access:** Only select repositories → pick this repo.
5. **Permissions → Repository permissions → Contents:** Read and write.
6. Click **Generate token**. Copy it. Save it in your password manager.

### Deploy the function

```bash
supabase secrets set GITHUB_PAT=your-token-here
supabase secrets set GITHUB_OWNER=your-github-username
supabase secrets set GITHUB_REPO=your-repo-name
supabase functions deploy cm-write --no-verify-jwt
```

## Step 3 — Try it

1. Open the board in your browser.
2. Click **+ Add story**.
3. It will ask for your name and a GitHub token. This is YOUR personal token (not the server one — create a second one the same way, or reuse if you want).
4. Fill in the form. Click **Create story**.
5. The ticket should appear in the backlog.

**Team setup is done.** The board remembers your name and token.

---

## Adding people to the team

Someone else on the setup person's GitHub repo wants to use the board:

1. The setup person adds them as a **GitHub collaborator** on the repo (repo → Settings → Collaborators → Add people).
2. They create their own GitHub token (same steps as [Create a GitHub token for the server](#create-a-github-token-for-the-server), but just for themselves — takes 2 minutes).
3. They open the board, click **Add story**, enter their name and token once. Done.

**Removing someone:** Remove them as a GitHub collaborator. Their token stops working immediately.

---

## Troubleshooting

| What you see | What to do |
|---|---|
| Board loads but no live indicator | Check `supabase_url` and `supabase_publishable_key` in `change-mate/config.json` |
| Add story says "Network error" | The cm-write function isn't deployed. Do [Deploy the function](#deploy-the-function). |
| Add story says "Access denied" | Your GitHub token doesn't have push access to this repo. Create a new one (see [Adding people to the team](#adding-people-to-the-team), step 2). |
| `PGRST002` error | Data API is off. Supabase → Settings → API → Data API → Enable → Save. |
| Everything stopped working | Free Supabase projects pause after ~1 week. Go to dashboard → click **Restore**. |

---

## For developers

```bash
py -m pytest -v                    # run all tests
bash change-mate/build.sh                      # rebuild board locally (don't commit the output)
deno test --allow-env supabase/functions/cm-write/   # run Edge Function tests
```

Future migrations go in `supabase/migrations/NNNN_*.sql`. Apply them in the SQL editor. They're all idempotent.
