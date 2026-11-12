---
description: Apply a live/stacks stack to real AWS through the live-drill workflow, screenshot the console, verify the destroy, write it up
argument-hint: <stack> [15|30|60]
---

# /live-drill $ARGUMENTS

You are running a **live drill** for Rodrigo, at his Mac, in local Claude Code. It applies
`live/stacks/<stack>` to his real AWS account through `.github/workflows/live-drill.yml`, captures console
screenshots during the hold, confirms the destroy, and commits a write-up. Background and costs: the
README's "Live drills" section and `live/bootstrap/README.md`.

Rules for the whole run:
- **Rodrigo approves every deployment.** Never approve an `aws-live` deployment unless he says yes in this
  chat for that specific job. Never dispatch the reaper, never edit `live/bootstrap/`.
- **No account identifiers in chat, files or commits.** Don't print the account ID, account alias, email or
  user name. Refer to the caller ARN as `arn:aws:iam::<ACCOUNT_ID>:user/<name>`.
- You never run `terraform apply` or `destroy` yourself. The workflow does.
- If the destroy fails at any point, stop everything else and go to step 6.

## 0. Arguments

`$1` is the stack, `$2` the hold in minutes (default `30`).
- The stack must be a folder in `live/stacks/` and an option in `live-drill.yml`. If not, list the valid
  stacks and stop.
- The hold must be 15, 30 or 60.
- `DATE="$(TZ=America/New_York date +%F)"`. Results go to `docs/live/$DATE-<stack>.md` and
  `docs/live/$DATE-<stack>/`; unredacted originals to `docs/live/.raw/$DATE-<stack>/` (gitignored).

## 1. Preflight (stop at the first failure and say why)

1. **Identity.** `aws sts get-caller-identity --query Arn --output text` must be the admin user
   (`...:user/rodrigo-admin`). If it ends in `:root`, stop: drills never run with root credentials.
2. **Budget.** `aws budgets describe-budgets --account-id "$(aws sts get-caller-identity --query Account --output text)" --query 'length(Budgets)'`
   must be at least 1. The budget emails are the alarm if anything is left running; no budget, no drill.
3. **main is green.** `git fetch origin`, then the latest `ci` run on `main` must be for `origin/main` and
   have succeeded: `gh run list --workflow ci.yml --branch main --limit 1 --json headSha,conclusion`
   (compare `headSha` with `git rev-parse origin/main`). That run is `scripts/check.sh` on main. You may also
   run `scripts/check.sh` locally in a clean worktree of `origin/main`.
4. **Nothing else running.** `gh run list --workflow live-drill.yml --limit 5 --json status,url` shows no run
   that isn't `completed`.

## 2. Dispatch and the apply approval

```bash
gh workflow run live-drill.yml --ref main -f stack=<stack> -f hold_minutes=<hold>
sleep 5
gh run list --workflow live-drill.yml --limit 1 --json databaseId,url,createdAt   # RUN=<databaseId>
```

Give Rodrigo the run URL and ask him to approve the **apply** job of the `aws-live` deployment. He can
approve in the browser, or say yes here; only then approve through the API:

```bash
REPO=rodrigopimenta10/aws-platform-terraform
ENV_ID="$(gh api "repos/$REPO/actions/runs/$RUN/pending_deployments" --jq '.[0].environment.id')"
gh api -X POST "repos/$REPO/actions/runs/$RUN/pending_deployments" \
  -F "environment_ids[]=$ENV_ID" -f state=approved -f comment="Approved by Rodrigo in chat"
```

## 3. Apply done: destroy approval, then screenshots

1. Poll until the apply job finishes:
   `gh run view "$RUN" --json jobs --jq '.jobs[] | select(.name=="apply") | [.status, .conclusion] | @tsv'`.
   If apply **failed**, tell Rodrigo, ask him to approve the destroy job (it cleans up with no hold), skip
   the screenshots, and continue at step 4.
2. The **destroy** job now waits for approval, and its hold starts only once it is approved. Ask Rodrigo to
   approve it now (same API call as above, only on his yes). The screenshot window is the hold.
3. Download the evidence (artifacts are available while the run is still going):
   `gh run download "$RUN" -n "live-evidence-<stack>-$RUN" -D "docs/live/$DATE-<stack>/evidence"`.
   Read `summary.md` (the job summary: resources by type, console links) and `outputs.json`.
4. **Screenshots**, one per entry under `<stack>:` in `live/screenshots.yml`, in Rodrigo's signed-in Chrome
   (Claude in Chrome), console signed in as `rodrigo-admin`:
   - Build the URL: replace `{region}` and each `{<output>}` with values from `outputs.json`.
   - Navigate, do what `then` says, wait until the page has finished loading, and check it shows what
     `proves` says. If the URL lands somewhere else, navigate there by hand and fix the URL in
     `live/screenshots.yml` (part of this drill's commit).
   - Bring Chrome to the front and capture **only the page area** of the window, not the desktop, the tab
     strip or other apps: `screencapture -x -R<x>,<y>,<w>,<h> "docs/live/.raw/$DATE-<stack>/<name>.png"`.
5. **Redact** each image into the repo folder. Look at the image first, then black out at least the
   console's top navigation bar (it shows the user name, account ID or alias and the region menu) and
   anything else identifying: account IDs (12 digits, also inside ARNs and "Owner ID" or "Owner" fields),
   account alias or name, email addresses, user names.
   ```bash
   magick "docs/live/.raw/$DATE-<stack>/<name>.png" \
     -fill black -draw "rectangle 0,0 <width>,<top-bar-height>" \
     -draw "rectangle <x0>,<y0> <x1>,<y1>" \
     "docs/live/$DATE-<stack>/<name>.png"
   ```
6. **Check every redacted image yourself**: open each one and confirm nothing identifying is visible. Redo
   any that fail. Only then delete the originals: `rm -rf "docs/live/.raw/$DATE-<stack>"`.
7. If the hold might run out before you finish, tell Rodrigo which screenshots are missing; never delay the
   destroy.

## 4. Destroy done

1. Poll the destroy job like the apply job. When it finishes:
   `gh run download "$RUN" -n "live-destroy-<stack>-$RUN" -D "docs/live/$DATE-<stack>/evidence"`.
   `destroy.json` must say `"destroy_verified": true` and the job must have succeeded. Anything else: step 6.
2. Check the evidence holds no account ID before it goes near git:
   `grep -rlE '[0-9]{12}' "docs/live/$DATE-<stack>/evidence"` must print nothing (if it flags a number that
   isn't an account ID, look before deciding).

## 5. Write it up and commit

Write `docs/live/$DATE-<stack>.md`:
- What was applied: the stack, the commit SHA (`timing.json`), the run URL, who approved.
- Resource counts by type (from `summary.md`).
- The screenshots, each with its one line from `live/screenshots.yml`:
  `![<name>](<DATE>-<stack>/<name>.png)`.
- Evidence highlights from the JSON (for `vpc`: CIDR, DNS attributes, subnets per tier and AZ with their
  CIDRs, routes per route table, default security group rules, NAT gateways = 0), linking to the files in
  `evidence/`.
- Measured times: apply (`apply_seconds`), destroy (`destroy_seconds`), and the hold.
- AWS cost estimate for the hold: list any hourly-billed resources in the state (NAT gateways, EKS clusters,
  load balancers, KMS keys, public IPv4 addresses...) with the price from the AWS pricing page you looked up
  (cite it), times the hours they existed. For `vpc` it is $0: none of its resources is billed
  ([VPC pricing](https://aws.amazon.com/vpc/pricing/)).
- **Destroy verified** (state empty, no resource tagged `live-stack=<stack>` left).

Show Rodrigo the write-up and the redacted screenshots. After he says OK, commit in the repo's style
(Conventional Commit subject, the `Co-Authored-By: Claude ...` trailer exactly as `git log -1` shows it):

```bash
git switch main && git pull --rebase
git add "docs/live/$DATE-<stack>.md" "docs/live/$DATE-<stack>/"   # plus live/screenshots.yml if you fixed a URL
git commit    # subject: docs(live): <stack> drill <DATE>
git push origin main
```

## 6. If the destroy failed

Stop and tell Rodrigo at once: resources may still be running and billing. Give him the run URL and the
manual destroy, to run as `rodrigo-admin` from the repo root:

```bash
export AWS_REGION=us-east-1
BUCKET="$(aws s3api list-buckets --query "Buckets[?starts_with(Name, 'platform-live-tfstate-')].Name" --output text)"
cd live/stacks/<stack>
terraform init -reconfigure -backend-config="bucket=$BUCKET" \
  -backend-config="key=live/<stack>/terraform.tfstate" \
  -backend-config="region=us-east-1" -backend-config="use_lockfile=true"
terraform destroy -var "region=us-east-1"
terraform state list                  # must print nothing
../../verify-destroyed.sh <stack>     # must say nothing remains
```

Re-running the failed destroy job from the Actions page (it needs his approval again) is the other option.
Don't write the drill up as a success; record the failure and how it was fixed instead.
