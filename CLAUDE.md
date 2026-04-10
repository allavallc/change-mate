# change-mate — Claude notes

## Board
- `change-mate-board.html` is auto-rebuilt by GitHub Actions on every push to `main` — never run `bash build.sh` manually
- `build.sh` requires Python 3 (`py` / `python3` / `python`)

## Config
- `change-mate-config.json` holds `gist_id` (for live lock registry) and `project_name`
- Live lock registry requires `CHANGEMATE_GITHUB_TOKEN` env var with Gist read/write scope

## Workflow
- `CHANGEMATE.md` is the authoritative workflow spec — edit it for any workflow changes, never the board HTML
