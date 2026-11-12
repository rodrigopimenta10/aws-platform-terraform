# live/bootstrap

The one-time stack behind the [live drill](../../README.md#live-drills). An account admin applies it **by
hand, once**. No agent and no workflow ever applies it (`.claude/daily-run.md` forbids the daily routine
from editing this folder at all). It creates:

| Resource | Why |
|---|---|
| S3 bucket + KMS key (via [`modules/state-backend`](../../modules/state-backend/), project `platform`, environment `live`) | Holds the Terraform state of every drill stack (`live/<stack>/terraform.tfstate`) and of this stack (`bootstrap/terraform.tfstate`). |
| GitHub Actions **OIDC identity provider** (`token.actions.githubusercontent.com`) | Lets AWS trust short-lived tokens that GitHub issues to a workflow run, so no AWS access keys are stored in GitHub. |
| IAM role **`platform-live-drill`** | What the drill workflow becomes in AWS. Only the `aws-live` environment of this repo can assume it, for at most one hour. |

**Cost:** about $1 a month for the KMS key ([KMS pricing](https://aws.amazon.com/kms/pricing/)) plus
cents of S3 storage. The OIDC provider and the role are free.

Nothing here is account-specific in git: the account ID comes from `aws_caller_identity` at plan time, the
bucket name is derived from it, and the backend values are passed with `-backend-config`. Override any
input in a `terraform.tfvars` here (gitignored) or with `-var`.

## Inputs

| Name | Type | Default | Description |
|------|------|---------|-------------|
| `region` | `string` | `"us-east-1"` | The only region drills may use, and where the bucket lives. |
| `owner` | `string` | `"platform-team"` | Owner tag. No email addresses. |
| `github_repository` | `string` | `"rodrigopimenta10/aws-platform-terraform"` | Repo allowed to assume the role. No wildcards. |
| `github_environment` | `string` | `"aws-live"` | GitHub environment the job must run in. |
| `max_session_duration` | `number` | `3600` | Role session limit in seconds, 900-3600. |

## Outputs

| Name | Description |
|------|-------------|
| `role_arn` | Goes into the `AWS_LIVE_ROLE_ARN` secret of the `aws-live` environment. |
| `state_bucket_name` | Goes into the `AWS_LIVE_STATE_BUCKET` secret of the `aws-live` environment. |
| `region` | Goes into the `AWS_LIVE_REGION` repository variable. |
| `oidc_provider_arn` | For M2.2, which imports this provider instead of creating a second one. |
| `state_kms_key_arn` | The bucket's default encryption key (drill backends don't need it, see below). |

## The trust policy

```json
"Principal": { "Federated": "arn:aws:iam::<ACCOUNT_ID>:oidc-provider/token.actions.githubusercontent.com" },
"Action": "sts:AssumeRoleWithWebIdentity",
"Condition": { "StringEquals": {
  "token.actions.githubusercontent.com:aud": "sts.amazonaws.com",
  "token.actions.githubusercontent.com:sub": "repo:rodrigopimenta10@11894505/aws-platform-terraform@1451999319:environment:aws-live"
} }
```

GitHub sets `sub` (the token's subject) to `repo:<owner>@<owner id>/<repo>@<repo id>:environment:<name>` for
a job that declares an `environment`. The numeric IDs (`github_owner_id`, `github_repository_id`) are in the
subject for this repository: the first drill, on 2026-11-12, was refused by a role that expected the older
`repo:<owner>/<repo>:environment:<name>` form, and CloudTrail showed the subject GitHub actually sent. Because
the IDs never change, a renamed or re-created repository with the same name cannot match. A job on a branch without that environment, a pull request, a fork or any other repository
gets a different `sub`, so `StringEquals` rejects it. The `aws-live` environment is what turns this into a
human decision: it requires Rodrigo's approval for every job and only accepts runs from `main`. AWS's own
[guidance for GitHub OIDC roles](https://docs.aws.amazon.com/IAM/latest/UserGuide/id_roles_create_for-idp_oidc.html)
recommends exactly this pairing of a tight `sub` and environment protection rules. (AWS's
[Terraform prescriptive guidance](https://docs.aws.amazon.com/prescriptive-guidance/latest/terraform-aws-provider-best-practices/security.html)
also suggests adding a `token.actions.githubusercontent.com:ref` condition for `refs/heads/main`. It is left
out here to keep the trust condition exactly as designed; the environment's "main only" rule enforces the
same thing on the GitHub side.)

## The trade-off: AdministratorAccess plus explicit denies

Drill stacks will grow with the roadmap: a VPC today, then EKS, IAM roles, Lambda, API Gateway, SQS,
DynamoDB, CloudWatch and Budgets. A least-privilege policy would need hand edits before every new
milestone could be drilled, and a too-narrow policy fails halfway through an apply or, worse, a destroy.
So the role gets the AWS managed `AdministratorAccess` policy, and an inline `live-drill-guardrails`
policy of **explicit denies**. In IAM an explicit Deny always beats an Allow, so these hold whatever
AdministratorAccess grants:

| Statement | Denies | Why |
|---|---|---|
| `DenyOutsideDrillRegion` | Every action not in a short list of global services, when `aws:RequestedRegion` isn't `us-east-1` | Nothing can be started (and forgotten) in a region nobody looks at. |
| `DenyBucketsOutsideDrillRegion` | `s3:CreateBucket` with a `LocationConstraint` other than `us-east-1` | `aws:RequestedRegion` only says which endpoint was called; a bucket for another region can be created through the us-east-1 endpoint. |
| `DenyLongLivedIdentitiesAndAccountChanges` | `iam:CreateUser`, `iam:CreateAccessKey`, `iam:CreateLoginProfile`, `iam:UpdateLoginProfile`, `organizations:*`, `account:*` | No identity or key that outlives the one-hour session; no account-level changes. |
| `DenyChangesToThisRole` | Attaching, putting, detaching or deleting policies, changing the trust policy or boundary, tagging, deleting or passing `platform-live-drill` | The role can't widen itself or remove its own guardrails. |
| `DenyChangesToGitHubOidcProvider` | Deleting or changing the OIDC provider | Nobody can swap the identity provider the trust policy relies on. |
| `DenyChangesToStateBucket`, `DenyErasingStateHistory`, `DenyWritesToBootstrapState`, `DenyDisablingStateKey` | Deleting or weakening the state bucket, deleting object versions, writing this stack's own state, disabling or scheduling deletion of the state key | A drill can manage its own `live/<stack>/` state but cannot destroy the drill infrastructure or its history. |

### How the region rule treats global services

`aws:RequestedRegion` is the region of the endpoint a request goes to. IAM, CloudFront, Route 53, Support,
Budgets and Cost Explorer have one global endpoint, physically in us-east-1, so their calls always carry
`us-east-1` ([global condition keys, `aws:RequestedRegion`](https://docs.aws.amazon.com/IAM/latest/UserGuide/reference_policies_condition-keys.html#condition-keys-requestedregion)).
With the drill region set to us-east-1 they would pass anyway. They are still listed in the statement's
`NotAction`, as in [AWS's example policy](https://docs.aws.amazon.com/IAM/latest/UserGuide/reference_policies_examples_aws_deny-requested-region.html),
so the policy stays correct if `region` ever changes. STS is listed because it also has **regional**
endpoints: a client configured for another region would otherwise fail even `GetCallerIdentity`. KMS, S3,
EC2, EKS and the rest are regional and stay denied outside us-east-1. Global services whose single endpoint
is in us-west-2 (for example Amazon Q Developer in chat applications, AWS Device Farm) stay denied on
purpose: no drill uses them.

### What the guardrails do not stop

This is a seatbelt, not a sandbox. With AdministratorAccess the role can still create other IAM roles,
including one that trusts another AWS account, or attach broad policies to roles it creates. Those
abilities are needed to drill EKS and IAM work, and the M2.3 permission boundary is the roadmap item that
will narrow them. What actually keeps the role safe:

1. **Every assumption is a human decision.** Only a job in the `aws-live` environment can get a token with
   the right `sub`, and that environment requires Rodrigo's approval and accepts only `main`.
2. **Short sessions.** Credentials last one hour at most and are never stored.
3. **Everything is in public git.** The workflows and stacks the role runs are reviewed code on `main`.
4. **Budget alerts** on the account are the alarm if anything is left running.

## Apply it (once, by an account admin)

1. Sign in with an admin user, **not root**, and load the pinned toolchain:
   ```bash
   aws sts get-caller-identity          # must show your admin user's ARN, not :root
   . ~/.local/aws-platform-tools/env.sh # Terraform 1.17.1 from scripts/bootstrap.sh
   export AWS_REGION=us-east-1
   cd live/bootstrap
   ```
2. Switch this first run to local state. `*_override.tf` is gitignored, and a backend block in an
   [override file](https://developer.hashicorp.com/terraform/language/files/override) takes precedence
   over the empty `backend "s3" {}` in `versions.tf`:
   ```bash
   printf 'terraform {\n  backend "local" {}\n}\n' > backend_override.tf
   terraform init
   terraform plan -out=bootstrap.tfplan
   ```
   The plan must show **13 to add, 0 to change, 0 to destroy**:
   - `module.state_backend`: `aws_kms_key.state`, `aws_kms_alias.state`, `aws_s3_bucket.state`,
     `aws_s3_bucket_versioning.state`, `aws_s3_bucket_server_side_encryption_configuration.state`,
     `aws_s3_bucket_public_access_block.state`, `aws_s3_bucket_ownership_controls.state`,
     `aws_s3_bucket_policy.state`, `aws_s3_bucket_lifecycle_configuration.state`
   - `aws_iam_openid_connect_provider.github`, `aws_iam_role.drill`,
     `aws_iam_role_policy_attachment.administrator`, `aws_iam_role_policy.guardrails`

   If it plans to create the OIDC provider but the account already has one for
   `token.actions.githubusercontent.com`, the apply will fail (one per URL). Import it first:
   `terraform import aws_iam_openid_connect_provider.github <its ARN>`.
3. Apply and note the outputs:
   ```bash
   terraform apply bootstrap.tfplan
   terraform output
   ```

## Move the state into the bucket

The stack's state is now in a local `terraform.tfstate` (gitignored). Move it into the bucket it just
created, under `bootstrap/terraform.tfstate`:

```bash
BUCKET="$(terraform output -raw state_bucket_name)"
rm backend_override.tf
terraform init -migrate-state \
  -backend-config="bucket=$BUCKET" \
  -backend-config="key=bootstrap/terraform.tfstate" \
  -backend-config="region=us-east-1" \
  -backend-config="use_lockfile=true"
# Terraform asks "Do you want to copy existing state to the new backend?": answer yes.
terraform plan                                # must say "No changes."
aws s3 ls "s3://$BUCKET/bootstrap/"           # terraform.tfstate is there
rm -f terraform.tfstate terraform.tfstate.backup bootstrap.tfplan
```

`encrypt` is deliberately not set: with `encrypt = true` and no `kms_key_id`, the S3 backend asks for
SSE-S3 (AES256) on every write, overriding the bucket's default ([`put` in the backend's client](https://github.com/hashicorp/terraform/blob/main/internal/backend/remote-state/s3/client.go)).
Leaving it unset lets the bucket's default SSE-KMS with the state key apply, without putting the key ARN
(which contains the account ID) anywhere.

Later changes from a fresh clone use the same `init` without `-migrate-state`. To find the bucket name:
`aws s3api list-buckets --query "Buckets[?starts_with(Name, 'platform-live-tfstate-')].Name" --output text`.

## Connect GitHub

The role ARN and bucket name both contain the account ID, and this repo's Actions logs are public. GitHub
prints the inputs of every step in the log, and repository **variables** are not masked there, so these two
go into **secrets** of the `aws-live` environment (masked as `***`, and only released to jobs that passed
the environment's approval). The region is not sensitive and stays a repository variable.

```bash
REPO=rodrigopimenta10/aws-platform-terraform

# Environment: Rodrigo must approve, self-review allowed, deployments from main only.
gh api -X PUT "repos/$REPO/environments/aws-live" --input - <<'JSON'
{
  "wait_timer": 0,
  "prevent_self_review": false,
  "reviewers": [{ "type": "User", "id": 11894505 }],
  "deployment_branch_policy": { "protected_branches": false, "custom_branch_policies": true }
}
JSON
gh api -X POST "repos/$REPO/environments/aws-live/deployment-branch-policies" -f name=main -f type=branch

# Values from this stack's outputs, piped so they never appear on screen or in shell history.
terraform output -raw role_arn          | gh secret set AWS_LIVE_ROLE_ARN     --env aws-live --repo "$REPO"
terraform output -raw state_bucket_name | gh secret set AWS_LIVE_STATE_BUCKET --env aws-live --repo "$REPO"
gh variable set AWS_LIVE_REGION --repo "$REPO" --body us-east-1
```

(`11894505` is the GitHub user ID of `rodrigopimenta10`: `gh api users/rodrigopimenta10 --jq .id`.)

## Testing

`tests/unit.tftest.hcl` uses `mock_provider "aws"` with `command = plan`. It replaces `module.state_backend`
with fixed outputs (that module has its own tests) so every policy is known at plan time, then checks the
role name and one-hour session, the provider's URL and audience, that the trust policy has one statement
with exact `sub` and `aud` matches, that the guardrails are Deny-only, which services are exempt from the
region rule (and that regional ones are not), the identity, self-protection and state-bucket statements,
and that wildcard repositories and longer sessions are rejected. There is no Moto test: by default Moto
stores IAM policies without evaluating them, so an apply against it would prove nothing more. Whether the
guardrails work for real is checked by the first drill.
