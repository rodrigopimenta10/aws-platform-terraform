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
   and get reviewed in today's note. Commits whose committer is `github-actions[bot]` are drill
   reports (`docs(live): ...`), not Rodrigo's work.
7. Read the newest report in `docs/live/` (the drill that ran after your last push). If its destroy is
   not verified, or a screenshot or the apply failed because of repo code, fixing that is today's first
   job, before the roadmap item.

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
5. **Make it drillable the same day.** After you push, GitHub applies every `live/stacks/<stack>` your
   push changed into the real account, screenshots it and destroys it (live/README.md). So when the item
   adds or changes a module, wire it into a drill stack in the same push: the current milestone's stack
   `live/stacks/m<N>/` (create it from `live/stacks/vpc` if it doesn't exist), plus its entries in
   `live/screenshots.yml` (structured `steps:`; see the header there). Use the cheapest settings that
   still prove the module works: 2 AZs, at most 1 NAT gateway, interface endpoints in at most 2 subnets,
   EKS with 1 node group of at most 2 `t3`/`t4g` nodes, `force_destroy = true`, the shortest KMS
   deletion window. `live/plan-gate.sh` refuses anything bigger, and the drill role only allows the
   services listed in `live/bootstrap/main.tf`.
   - Every `aws_iam_role` a module creates must accept a `permissions_boundary` variable (default
     `null`), and drill stacks pass `var.permissions_boundary_arn` (the workflow sets
     `TF_VAR_permissions_boundary_arn`). The drill role cannot create a role without that boundary.
   - Add a note to today's learning note: what the drill will show and what it should cost.

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
  Link the milestone's latest drill report in `docs/live/`; it is the "for real" evidence.

## 5. Push
1. `scripts/check.sh` must print `ALL CHECKS PASSED`.
2. `git pull --rebase` then `git push origin main`.
3. If you couldn't get the checks green after three honest attempts, don't push broken work.
   `git reset --hard origin/main` and end with a short summary of what blocked you.
   A day with no push is fine.

## Never
- Edit `CLAUDE.md`, this file, or `docs/daily/TEMPLATE.md`. (You may fix `scripts/` only if a check is
  broken by the environment, and say so in the note.)
- Use real AWS credentials, apply against anything but Moto, or add secrets.
- Change past daily notes, rewrite history, force-push, or fake commit dates.
- Work on anything outside `ROADMAP.md`. If the roadmap is finished, write a final note saying so and stop.
- Dispatch workflows, approve deployments, or edit the drill machinery: `live/bootstrap/`, `live/*.sh`,
  `live/*.mjs`, anything under `.github/`, `scripts/check-live-stacks.sh` or `.tool-versions`. (The drill
  refuses pushes that touch them anyway.) Never edit `docs/live/` reports either: the workflow writes them.

## Finish
End with a three-line summary: the item(s) done, commit count, and anything Rodrigo should look at.
