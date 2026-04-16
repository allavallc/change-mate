# Setting up change-mate

This guide takes you from zero to a fully working board. Every step tells you exactly what to click and what to type. If something doesn't match what you see on screen, check the [Troubleshooting](#troubleshooting) section at the bottom.

There are two levels:

| Level | What you get | Time |
|---|---|---|
| **Basic** (step 1 only) | A board you can view. No creating tickets from the browser. | 2 minutes |
| **Full** (steps 1–3) | Everything: live updates, create tickets from the board, per-person write keys. | 15 minutes |

---

## Step 1 — Install change-mate in your project

Open a Claude Code session in your project and say:

```
I want to use change-mate. Set it up from https://github.com/allavallc/change-mate
```

Or run the installer manually in your terminal:

```bash
curl -fsSL https://raw.githubusercontent.com/allavallc/change-mate/main/setup.sh | bash
```

Then save it to your repo:

```bash
git add change-mate/ CHANGEMATE.md CLAUDE.md
git commit -m "add change-mate"
git push
```

**You now have a board.** Open `change-mate-board.html` to see it:

- **On your computer**: double-click the file in your file explorer. It opens in your browser.
- **Shared link for your team**: go to your GitHub repo → **Settings → Pages → Build from branch → `main` / root → Save**. Your board will be at:
  `https://your-username.github.io/your-repo/change-mate-board.html`

If you only want to view the board (no creating tickets from the browser), **you're done.** Stop here.

---

## Step 2 — Connect to Supabase (live updates + ticket creation)

This step gives the board a database so it can show live updates and let people create tickets directly from the browser. You'll create a free Supabase project — it takes about 10 minutes.

### 2.1 — Create a Supabase account and project

1. Go to **[supabase.com/dashboard](https://supabase.com/dashboard)**.
2. Click **Sign in** (or **Sign up** — you can use your GitHub account to sign in).
3. Once you're in the dashboard, click **New project**.
4. Fill in:
   - **Name**: anything you'll recognise later, like `change-mate`
   - **Database Password**: click **Generate a password**. Save it in your password manager just in case.
   - **Region**: pick whichever is closest to you
5. Click **Create new project**. It takes about 2 minutes to set up. Wait until the page shows your project dashboard.

### 2.2 — Copy your project's connection details

1. In the Supabase sidebar (left side), click the **gear icon** at the bottom → **API**.
2. You'll see two values you need. Copy each one and paste it somewhere you can find it (a text file, a sticky note, whatever works):
   - **Project URL** — looks like `https://abcdefg.supabase.co`
   - **anon public key** — a long string starting with `sb_publishable_` or `eyJ`

   **Do NOT copy the `service_role` key.** That one is secret and should never leave this page.

3. While you're still on this page, scroll down to **Data API**. If you see a toggle that says **Enable Data API**, turn it **ON**, make sure `public` appears in the dropdown, and click **Save**. (Some projects have this on already — if you don't see the toggle, you're fine.)

### 2.3 — Set up the database tables

1. In the Supabase sidebar, click **SQL Editor** (the `</>` icon).
2. Click **New query**.
3. On your computer, open the file `supabase/migrations/0001_initial.sql` from this repo. Select everything (Ctrl+A or Cmd+A), copy it (Ctrl+C or Cmd+C).
4. Go back to the Supabase SQL editor and paste it in.
5. Click **Run**.

You'll see a confirmation that says *"destructive operations"* — this is normal. It's just removing unnecessary permissions. Click **Run this query**.

You should see **Success. No rows returned.** That means it worked.

Now do the same thing with the second migration:

1. Click **New query** again.
2. Open `supabase/migrations/0002_ticket_id_sequence.sql` from this repo. Select all, copy.
3. Paste into the SQL editor and click **Run**.

Again, you should see **Success. No rows returned.**

### 2.4 — Connect change-mate to your Supabase project

Open `change-mate-config.json` in this repo (it's at the root). Update it with your values:

```json
{
  "gist_id": "",
  "project_name": "my project",
  "supabase_url": "https://abcdefg.supabase.co",
  "supabase_publishable_key": "your-anon-key-here",
  "board_mode": "public-write"
}
```

Replace `https://abcdefg.supabase.co` with your actual Project URL, and `your-anon-key-here` with your actual anon public key.

The `board_mode` controls who can do what:

| Mode | Who can see the board | Who can create tickets |
|---|---|---|
| `public-readonly` | Anyone | Nobody (Add Story button hidden) |
| `public-write` | Anyone | Anyone with a write key |
| `private` | Only people with a write key | Only people with a write key |

Most teams should use `public-write`.

**If you use GitHub Actions** to auto-rebuild the board, also add these as repo secrets:

1. Go to your GitHub repo → **Settings → Secrets and variables → Actions**.
2. Click **New repository secret**. Name: `SUPABASE_URL`. Value: your Project URL. Click **Add secret**.
3. Click **New repository secret** again. Name: `SUPABASE_PUBLISHABLE_KEY`. Value: your anon key. Click **Add secret**.

### 2.5 — Verify everything is working

Run this in your terminal (at the root of this repo):

```bash
py scripts/verify_supabase.py
```

> On macOS/Linux, use `python3` instead of `py`.

You should see:

```
[PASS] write_keys is hidden from anon
[PASS] locks rejects anon INSERT
[PASS] ticket_events is readable by anon
All checks passed. RLS is correctly configured.
```

If you see `[FAIL]`, go back to step 2.3 and re-run the SQL. If you see `PGRST002`, go back to step 2.2 and make sure the Data API is enabled.

---

## Step 3 — Enable "Add Story" (create tickets from the board)

This step deploys a small server function that lets the board create tickets. Without it, the Add Story button won't work.

### 3.1 — Install the Supabase CLI

You need Node.js installed. Then run:

```bash
npm install -g supabase
```

> If you don't have Node.js, download it from [nodejs.org](https://nodejs.org/).

### 3.2 — Log in and link your project

```bash
supabase login
```

This opens your browser. Sign in to Supabase and approve the connection.

Then link your project:

```bash
supabase link --project-ref abcdefg
```

Replace `abcdefg` with your project ref — that's the part before `.supabase.co` in your Project URL. For example, if your URL is `https://abcdefg.supabase.co`, the ref is `abcdefg`.

### 3.3 — Create a GitHub token

The server function needs permission to create files in your repo. You'll give it a token that can only write to this one repo.

1. Go to **[github.com/settings/tokens?type=beta](https://github.com/settings/tokens?type=beta)**.
2. Click **Generate new token**.
3. Fill in:
   - **Token name**: `change-mate`
   - **Expiration**: 90 days
   - **Repository access**: click **Only select repositories** → pick this repo
   - **Permissions**: expand **Repository permissions** → find **Contents** → set to **Read and write**
4. Leave everything else as-is.
5. Click **Generate token**.
6. **Copy the token immediately** — you won't be able to see it again. Save it in your password manager.

### 3.4 — Deploy the function

Run these three commands. Replace the placeholders with your actual values:

```bash
supabase secrets set GITHUB_PAT=your-github-token-here
supabase secrets set GITHUB_OWNER=your-github-username
supabase secrets set GITHUB_REPO=your-repo-name
supabase functions deploy cm-write --no-verify-jwt
```

For example, if your GitHub is `janedoe` and your repo is `my-project`:

```bash
supabase secrets set GITHUB_OWNER=janedoe
supabase secrets set GITHUB_REPO=my-project
```

When the deploy finishes, you'll see a success message with a link to your Supabase dashboard.

### 3.5 — Create your write key

A write key is like a password that lets you create tickets. Each person gets their own. The board will ask for it the first time you click Add Story, and remembers it in your browser after that.

**Pick any secret string** — a password, a random phrase, anything you'll remember. Or generate a random one:

- **macOS/Linux**: `openssl rand -hex 32`
- **Windows PowerShell**: `-join ((1..32) | ForEach-Object { '{0:x2}' -f (Get-Random -Max 256) })`

**Save your key in your password manager.** You'll need to enter it in the board the first time.

Now register the key in Supabase. Go to the **SQL Editor** and run this (replace the two placeholders):

```sql
insert into public.write_keys (key_hash, label, role)
values (
  encode(sha256(convert_to('PASTE_YOUR_KEY_HERE', 'UTF8')), 'hex'),
  'Your Name',
  'human'
);
```

- Replace `PASTE_YOUR_KEY_HERE` with the key you just created.
- Replace `Your Name` with your name (this shows up in the audit log when you create tickets).

### 3.6 — Test it

1. Open your board in a browser (rebuild it first with `bash build.sh`, or wait for GitHub Actions to rebuild it after your next push).
2. Click **+ Add story**.
3. The board will ask for your write key. Paste it in and click **Continue**.
4. Fill in a title, priority, and effort. Click **Create story**.
5. You should see a toast message saying the ticket was created.
6. Check your repo — a new file should appear in `change-mate/backlog/`.

**That's it. You're fully set up.**

---

## Giving other people access

Each person who needs to create tickets gets their own write key. Repeat step 3.5 for each person — pick a new key, register it with their name. They enter it in the board once and it's remembered.

To **revoke someone's access** (they left the team, key was leaked, etc.), run this in the SQL editor:

```sql
update public.write_keys
set revoked_at = now()
where label = 'Their Name';
```

The key stops working immediately. No redeploy needed. Next time they try to create a ticket, they'll see "Your write key has been revoked."

---

## Troubleshooting

| What you see | What to do |
|---|---|
| `PGRST002` error in verify script | The Data API is off. Go to Supabase → **Settings → API → Data API** → turn it **ON** → Save. If the project is paused (free tier), click **Restore** on the project card. |
| Board loads but no live indicator | Check that `supabase_url` and `supabase_publishable_key` are filled in correctly in `change-mate-config.json`. |
| Add Story says "Network error" | The cm-write function isn't deployed. Go back to step 3.4. |
| Add Story says "Invalid write key" | The key you entered doesn't match any key in the database. Check that you registered it in step 3.5. Copy-paste it exactly — no extra spaces. |
| Add Story says "write key revoked" | Your key was revoked by an admin. Ask them for a new one, or create a new key yourself (step 3.5). |
| GitHub Actions board build fails | Check that `SUPABASE_URL` and `SUPABASE_PUBLISHABLE_KEY` are set as repo secrets (step 2.4). |
| SQL editor says "permission denied" | You're probably using the anon key somewhere. The SQL editor in the Supabase dashboard runs as admin — use that. |
| Everything was working, now nothing loads | Free-tier Supabase projects pause after ~1 week of inactivity. Go to your Supabase dashboard and click **Restore**. |

---

## For developers

### Running tests

```bash
py -m pytest -v
```

### Applying future migrations

When new `supabase/migrations/NNNN_*.sql` files appear in the repo, apply them one at a time in the Supabase SQL editor. Each migration is safe to re-run.

### Supabase verification SQL

Two deeper test scripts live in `supabase/tests/`:

- `verify.sql` — checks all tables, indexes, RLS flags, and policies
- `concurrent_lock_test.sql` — proves the atomic lock claim works correctly

Paste each into the SQL editor to run them. They clean up after themselves.
