# Setting up change-mate

Follow these steps in order. If you just want the basic board (no live lock registry, no history, no write keys), stop after step 1. If you want the full experience — live locking across agents, full audit history, per-person write keys — continue through step 2.

---

## 1. Install change-mate in your project

Inside a Claude Code session, say:

```
I want to use change-mate. Set it up from https://github.com/allavallc/change-mate
```

Or run the installer manually:

```bash
curl -fsSL https://raw.githubusercontent.com/allavallc/change-mate/main/setup.sh | bash
```

Then commit and push so your whole team picks it up:

```bash
git add change-mate/ CHANGEMATE.md CLAUDE.md
git commit -m "add change-mate"
git push
```

That's it — you now have a working board. `change-mate-board.html` is a static single-file HTML page committed to your repo. Two common ways to view it:

- **Locally from disk.** Double-click `change-mate-board.html` in your file explorer, or drag-drop it into a browser tab. The address bar will show something like:
  - macOS / Linux: `file:///Users/you/projects/your-project/change-mate-board.html`
  - Windows: `file:///C:/Users/you/projects/your-project/change-mate-board.html`
- **Shared team link via GitHub Pages.** Enable Pages in your repo (**Settings → Pages → Build from branch → `main` / root**). The board becomes available at:
  - `https://<your-github-username>.github.io/<your-repo-name>/change-mate-board.html`

  Example: if your repo is `github.com/your-username/your-project`, the URL is `https://your-username.github.io/your-project/change-mate-board.html`.

Netlify / Vercel work too — point them at the repo root and deploy as a static site.

---

## 2. Provision Supabase (live locks, history, write keys)

**You need your own Supabase project.** Each change-mate deployment uses its own database — there is no shared backend. Anyone cloning a repo that uses change-mate follows the same five steps below.

> Write keys (per-person authentication) are configured later, once the `cm-write` Edge Function ships in a follow-up ticket. You do not need to generate one now.

### Step 2.1 — Create the Supabase project *(on supabase.com)*

1. Go to **[supabase.com/dashboard](https://supabase.com/dashboard)** and sign in (or sign up — GitHub login works).
2. Click **New project**.
3. Fill in:
   - **Name**: anything memorable (e.g. `change-mate-yourname`)
   - **Database Password**: click *Generate a password* and **save it in your password manager**. You probably won't need it again, but save it anyway.
   - **Region**: pick the one closest to you.
4. Click **Create new project**. Wait ~2 minutes for the project to provision.
5. When it's ready, click the **Project Settings** gear icon (bottom-left) → click **API** in the sidebar.
6. Copy these two values and keep them in a scratchpad — you'll paste them in step 2.3:
   - **Project URL** — looks like `https://xxxxxxx.supabase.co`
   - **anon public** key — starts with `sb_publishable_...` or `eyJhbGciOi...`

   ⚠️ Do **not** copy the `service_role` key. That one is a secret and must never leave the Supabase dashboard.

7. Still on the **Settings → API** page, scroll to the **Data API** section. New Supabase projects ship with the Data API *disabled* by default. Toggle **Enable Data API** to ON, make sure `public` is listed in the schema dropdown that appears, and click **Save**. Without this, the board can't read anything and the verify script in step 2.5 will fail with `PGRST002`.

### Step 2.2 — Apply the schema *(in the Supabase SQL editor)*

1. In the Supabase sidebar, click **SQL Editor** (the `</>` icon).
2. Click **New query**.
3. Open the file [`supabase/migrations/0001_initial.sql`](supabase/migrations/0001_initial.sql) from this repo on your computer. Select all (Ctrl/Cmd+A) and copy (Ctrl/Cmd+C).
4. Paste it into the Supabase SQL editor.
5. Click **Run** (bottom-right, or Ctrl/Cmd+Enter).

> **Expected warning on first run.** Supabase will pop a "destructive operations" confirmation because the script includes `revoke` statements that strip default privileges from the `anon` and `authenticated` roles. This is intentional. No data is being deleted. Click **Run this query**.

You should see *Success. No rows returned.* The script is safe to re-run anytime.

### Step 2.3 — Wire up change-mate *(edit one file + add two secrets)*

Open `change-mate-config.json` at the root of this repo in your editor. Paste your two values into the `supabase_url` and `supabase_publishable_key` fields. The complete file should look like this:

```json
{
  "gist_id": "",
  "project_name": "my project",
  "supabase_url": "https://xxxxxxx.supabase.co",
  "supabase_publishable_key": "sb_publishable_..."
}
```

> JSON is strict: keep every comma, every quote, and the surrounding `{ }`. Nothing after the closing `}`.

For automated board rebuilds via GitHub Actions, also add those same two values as repo secrets:

1. In your GitHub repo → **Settings → Secrets and variables → Actions**.
2. Click **New repository secret**. Name = `SUPABASE_URL`, value = your Project URL. Click **Add secret**.
3. Click **New repository secret** again. Name = `SUPABASE_PUBLISHABLE_KEY`, value = your anon key. Click **Add secret**.

### Step 2.4 — Verify the schema *(in the Supabase SQL editor)*

Open a new query in the SQL editor and paste these two queries:

```sql
-- Expect exactly 3 rows: locks, ticket_events, write_keys
select table_name
from information_schema.tables
where table_schema = 'public'
  and table_name in ('locks', 'ticket_events', 'write_keys');

-- Expect true / true in every row for all three tables
select relname, relrowsecurity, relforcerowsecurity
from pg_class
where relname in ('locks', 'ticket_events', 'write_keys');
```

If the row counts and flags match what's in the comments, the schema is correctly installed.

### Step 2.5 — Verify RLS blocks anon writes *(run one command in your terminal)*

This proves the anon key can't do anything it shouldn't. Open a terminal **at the root of this repo** and run:

```bash
py scripts/verify_supabase.py
```

> On macOS/Linux use `python3 scripts/verify_supabase.py` instead of `py`.

The script reads `change-mate-config.json`, hits the Supabase REST API three times with your anon key, and prints one line per check. You want to see three `[PASS]` lines:

```
[PASS] write_keys is hidden from anon
[PASS] locks rejects anon INSERT
[PASS] ticket_events is readable by anon
All checks passed. RLS is correctly configured.
```

If you see `[FAIL]` on any line, re-apply `supabase/migrations/0001_initial.sql` (step 2.2) and run the script again.

Setup is complete. The board now reads Supabase for live lock state and ticket event history.

---

## Advanced verification *(optional — for developers)*

Two SQL files under `supabase/tests/` go deeper than the anon-key probe in step 2.5. Useful after editing the migration or debugging a deployment. Paste each into the Supabase SQL editor in turn:

- **`supabase/tests/verify.sql`** — asserts all tables, indexes, RLS flags, policies, and the `role` check constraint are present and shaped correctly. On success prints `===== ALL VERIFICATIONS PASSED =====`.
- **`supabase/tests/concurrent_lock_test.sql`** — proves the atomic claim semantics by inserting the same `ticket_id` twice and asserting the second insert is rejected by the PK unique constraint. Cleans up after itself.

The pytest suite (`py -m pytest`) also includes static-analysis tests of the migration file itself (`tests/test_migration_sql.py`) — no database needed, runs on every CI build.

---

## Managing migrations going forward

- Each new schema change lands as `supabase/migrations/NNNN_<slug>.sql`, zero-padded 4 digits, in order.
- Apply them one at a time in the Supabase SQL editor.
- Every migration is wrapped in `begin; ... commit;` and uses `if exists` / `if not exists` so re-runs are safe.
- Never edit an applied migration — add a new file instead.

---

## Troubleshooting

| Problem | Fix |
|---|---|
| Verify script reports "PostgREST schema cache is cold" / `PGRST002` | Three causes, check in order: **(1)** Data API is disabled — go to **Project Settings → API → Data API** and toggle **Enable Data API** on, make sure `public` is in the schema list, Save. New Supabase projects default to off. **(2)** Project is paused (free tier auto-pauses after ~1 week) — click **Restore** on the project card. **(3)** Project is still provisioning — wait 1–2 minutes |
| Board shows but no lock info | Check `change-mate-config.json` has `supabase_url` + `supabase_publishable_key` filled in |
| GitHub Actions board build fails | Check repo secrets `SUPABASE_URL` and `SUPABASE_PUBLISHABLE_KEY` are set |
| SQL editor says "permission denied" running the migration | You're using the anon key. Use the SQL editor in the Supabase dashboard — it runs as service role |
| Re-running `0001_initial.sql` throws errors | The script should be idempotent. Capture the exact error and file an issue |
