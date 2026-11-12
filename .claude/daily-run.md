# Daily run procedure

You are the daily builder for this repo. Read `CLAUDE.md` first and follow it. Work on `main` and push to
`main` (not a `claude/` branch). Rodrigo doesn't review before merging, so the checks are the review.

## 1. Set up
1. `bash scripts/bootstrap.sh`, then `. ~/.local/aws-platform-tools/env.sh`.
2. Set the commit identity to the repo owner, who directs this work (Claude stays credited through the
   `Co-Authored-By: Claude` trailer on every commit):
   `git config user.name "Rodrigo Pimenta"` and
   `git config user.email "11894505+rodrigopimenta10@users.noreply.github.com"`.
3. `export TZ=America/New_York` for the whole run. Rodrigo lives in that time zone, so commits should
   carry his local time and count on his local day. This sets the zone only. It is not a way to
   change dates: see "Never".
4. `git checkout main && git pull --ff-only`.
5. Read `ROADMAP.md`, the three newest files in `docs/daily/`, and the note from about a week ago
   (for the warm-up questions).
6. Run `git log --since="36 hours ago" --format='%h %an %s%n%b'` and note any commits that have no
   `Co-Authored-By: Claude` trailer. Those are Rodrigo's own (usually a "try it yourself" exercise)
   and get reviewed in today's note.

## 2. Make sure main is healthy
Run `scripts/check.sh`. If it fails on `main` before you change anything, today's job is fixing that.
Fix it, commit it as `fix: ...`, and explain the cause in today's note. Then continue if time allows.
If the break came from one of Rodrigo's commits, make the smallest fix that gets the checks green,
keep his approach, and explain what went wrong under "Feedback on your commits". Don't rewrite his
code to your taste when the checks pass.

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

- **Second run on the same day:** if today's note already exists, don't touch it. Write
  `YYYY-MM-DD-2.md` and commit it as `docs: daily note YYYY-MM-DD (2)`.
- **Warm-up questions:** follow the template. The point is recall after a gap, so pick the ideas that
  matter most in those older notes and ask them in a new way.
- **Feedback on Rodrigo's commits:** include the section when step 1.6 found any.
- **Milestone recap:** if today's item ticks the last box of a milestone, also write
  `docs/milestones/M<N>.md` and commit it as `docs: milestone M<N> recap`. Contents: how the
  milestone's modules fit together (a Mermaid diagram plus a paragraph), ten mixed questions across
  the whole milestone with collapsed answers, and an "Apply it for real" section: the exact commands
  for Rodrigo to apply this milestone in his own AWS account, what to look at in the console, the
  rough cost per hour, and the destroy and verify steps. You still never run those commands yourself.
  Also add or update `live/stacks/m<N>/` (a root module that applies this milestone's modules, cheapest
  settings, `force_destroy = true` and the shortest KMS deletion window where those exist) and its entry
  in `live/screenshots.yml`, and point the recap's "Apply it for real" section at `/live-drill m<N>`.
  This keeps every future milestone drillable without more setup. Add the new stack's name to the
  `stack` choice list in `.github/workflows/live-drill.yml` too: that one list is the only part of a
  `live-*.yml` workflow you may edit, and `scripts/check.sh` fails until the list matches `live/stacks/*`.

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
- Dispatch workflows, approve deployments, or edit `live/bootstrap/` or `.github/workflows/live-*.yml`.

## Finish
End with a three-line summary: the item(s) done, commit count, and anything Rodrigo should look at.
