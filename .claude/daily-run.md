# Daily run procedure

You are the daily builder for this repo. Read `CLAUDE.md` first and follow it. Work on `main` and push to
`main` (not a `claude/` branch). Rodrigo doesn't review before merging, so the checks are the review.

## 1. Set up
1. `bash scripts/bootstrap.sh`, then `. ~/.local/aws-platform-tools/env.sh`.
2. `git checkout main && git pull --ff-only`.
3. Read `ROADMAP.md` and the three newest files in `docs/daily/`.

## 2. Make sure main is healthy
Run `scripts/check.sh`. If it fails on `main` before you change anything, today's job is fixing that.
Fix it, commit it as `fix: ...`, and explain the cause in today's note. Then continue if time allows.

## 3. Build today's item
1. Take the first unchecked item in `ROADMAP.md`. If it's **S** and you finish with plenty of time left,
   you may also take the next item if it's **S**. Never take more than two items.
2. Build it to the "done" bar at the top of `ROADMAP.md`.
3. Commit as you go, one commit per logical change: module code, tests, docs, ADR, wiring. The number
   of commits should follow from the work, usually 1–6. Don't pad, don't squash.
4. Run `scripts/check.sh` before each commit when practical, and always before pushing.

## 4. Write today's learning note
Create `docs/daily/YYYY-MM-DD.md` (date from `TZ=America/New_York date +%F`) using
`docs/daily/TEMPLATE.md`. Tick the item in `ROADMAP.md` and update the "Status" line in `README.md`.
Commit as `docs: daily note YYYY-MM-DD`.

## 5. Push
1. `scripts/check.sh` must print `ALL CHECKS PASSED`.
2. `git pull --rebase` then `git push origin main`.
3. If you couldn't get the checks green after three honest attempts, don't push broken work.
   `git reset --hard origin/main` and end with a short summary of what blocked you.
   A day with no push is fine.

## Never
- Edit `CLAUDE.md`, this file, or `docs/daily/TEMPLATE.md`. (You may fix `scripts/` or `.github/` only if
  a check is broken by the environment, and say so in the note.)
- Use real AWS credentials, apply against anything but Moto, or add secrets.
- Change past daily notes, rewrite history, force-push, or fake commit dates.
- Work on anything outside `ROADMAP.md`. If the roadmap is finished, write a final note saying so and stop.

## Finish
End with a three-line summary: the item(s) done, commit count, and anything Rodrigo should look at.
