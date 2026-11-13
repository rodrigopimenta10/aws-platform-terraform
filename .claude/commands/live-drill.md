---
description: Start a live drill by hand (apply, screenshot, destroy in GitHub Actions) and read its report
argument-hint: "<stack | changed | all> [hold_minutes: 0|15|30|60]"
---

Live drills normally run by themselves after CI passes on `main` (see `live/README.md`). Use this command
when Rodrigo wants one now: to check a change to the protected drill files (which unattended drills
refuse), to re-drill a stack, or to keep a stack up for a while and look at it himself.

1. Preflight, from the repo root:
   - `gh run list --workflow live-drill.yml --limit 3`: if one is running, wait for it (one drill at a time).
   - `scripts/check.sh` passes on `main`, and `git status` is clean and pushed (the drill runs what is on `main`).
2. Start it: `gh workflow run live-drill.yml -f stack=<stack> -f hold_minutes=<0|15|30|60>`, then
   `gh run watch "$(gh run list --workflow live-drill.yml --limit 1 --json databaseId --jq '.[0].databaseId')"`.
   Nothing needs approving. With a hold, tell Rodrigo the stack is up and the console links are in the run's
   summary; he looks in his own browser as `rodrigo-admin`.
3. When it finishes: `git pull`, then read the report the workflow committed, `docs/live/<date>-<stack>.md`,
   and its screenshots. Tell Rodrigo: apply and destroy times, whether destroy was verified, which screenshots
   were captured or failed, and anything that went differently.
4. If destroy was not verified, say so first. `live-reaper.yml` retries hourly; to retry now,
   `gh workflow run live-reaper.yml`. Never destroy from this machine unless Rodrigo asks.
5. If a screenshot failed because its URL or `steps` in `live/screenshots.yml` were wrong, fix them, push,
   and the next drill retakes them.
