# Setting up change-mate

One path. ~2 minutes.

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

**Board visibility follows repo visibility.** Public repo = public board, world-readable at the URL above. Private repo = private board (requires GitHub Pro for private Pages).

If you want to keep the board off Pages output (but still in the repo), set Pages source to `/docs` instead of root — the board still exists at `change-mate/board.html` but isn't published. See [INSTALL-FAQ.md](change-mate/INSTALL-FAQ.md) for more.

## Step 3 — Add or move tickets

You can edit markdown files in the repo, or click **+ Add story** in the browser.

**To use the Add story button**, the board needs to write to your repo. Create a fine-grained PAT once:

1. Go to **[github.com/settings/tokens?type=beta](https://github.com/settings/tokens?type=beta)**.
2. Click **Generate new token**. Name it `change-mate`.
3. **Repository access:** Only select repositories → pick this repo.
4. **Permissions → Repository permissions → Contents:** Read and write.
5. Click **Generate token**, copy it, save it in your password manager.

Open the board → click **+ Add story** → enter your name and the token once. The token lives in your browser only and is never sent anywhere except GitHub.

## Step 4 — Live updates

The board polls the GitHub commits API every 30 seconds. When a teammate pushes a change, the page reloads automatically. No backend, no WebSocket, no service to manage.

To change the polling interval, add `"poll_seconds": 60` (or any value ≥10) to `change-mate/config.json`.

**That's it.**

---

## Adding people to the team

1. The repo owner adds them as a **GitHub collaborator** (repo → Settings → Collaborators → Add people).
2. They create their own fine-grained PAT (same steps as Step 3 above — takes 2 minutes).
3. They open the board, click **+ Add story**, enter their name and token once. Done.

**Removing someone:** Remove them as a GitHub collaborator. Their token stops working immediately.

---

## Troubleshooting

| What you see | What to do |
|---|---|
| Add story says "Network error" | Your fine-grained PAT is missing or invalid. Click + Add story again to re-enter it. |
| Add story says "Access denied" | Your token doesn't have **Contents: Read and write** on this repo. Regenerate it (Step 3). |
| Board doesn't update on someone else's push | Wait up to ~30s (polling interval) or hard-refresh. |
| GitHub API rate limit | Polling falls back gracefully after 5 failures. Refresh the page when you're ready to resume. |

---

## For developers

```bash
py -m pytest -v             # run all tests
bash change-mate/build.sh   # rebuild board locally (don't commit the output)
```
