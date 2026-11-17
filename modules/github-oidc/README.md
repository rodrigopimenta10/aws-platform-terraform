# github-oidc

Lets a GitHub Actions workflow deploy to AWS **without any stored access key**.

**OIDC** (OpenID Connect) is a standard way for one service to vouch for an identity to another. Every
GitHub Actions job can ask GitHub for a short-lived signed token that says, in effect, "this job runs in
repository X, on branch Y". AWS can be told to trust GitHub's signature. The job then trades the token to
**STS** (Security Token Service, AWS's issuer of temporary credentials) for credentials that last an hour.

This module creates two things:

- an **OIDC identity provider** in IAM: the entry that says "AWS trusts tokens signed by
  `token.actions.githubusercontent.com`" (optional, see `create_provider`);
- a **deploy role** whose **trust policy** (the document saying who may assume the role) accepts a token
  only if its audience is `sts.amazonaws.com` **and** its **subject** is one of the exact repository,
  branch, environment or pull request contexts you allowed.

The module gives the role **no permissions**. Trust says who may use the role; permissions say what it
can do. You attach those with `managed_policy_arns`.

## Why OIDC beats long-lived keys

| | Access key stored in GitHub secrets | OIDC role |
|---|---|---|
| Lifetime | Until someone rotates it, often never | One hour per job |
| If it leaks (logs, a fork, a compromised action) | Works from anywhere until noticed | Useless after the hour, and only accepted for a token GitHub signed for this repo |
| Rotation | A chore people forget | Nothing to rotate |
| Scope | The key works from any machine | Trust is tied to repo, branch or environment |
| Audit | "the CI user did it" | CloudTrail shows the repo and ref in the session name |

## What the token's subject looks like

GitHub builds the `sub` claim from the job's context:

| Job runs on | Subject |
|---|---|
| a branch push | `repo:<owner>/<repo>:ref:refs/heads/<branch>` |
| a job with `environment: <name>` | `repo:<owner>/<repo>:environment:<name>` |
| a pull request | `repo:<owner>/<repo>:pull_request` |

The trust policy lists the exact subjects with `StringEquals`. It never uses `StringLike` wildcards: with
`repo:<owner>/*` any repository you own (or, if the owner name is mistyped, someone else's) could assume
the role, and `refs/heads/*` would let anyone who can push a branch deploy.

If your repository's tokens carry numeric IDs (`repo:<owner>@<id>/<repo>@<id>:...`, as the drill
repository's do), set `github_owner_id` and `github_repository_id`. IDs never change, so a repository
deleted and re-created under the same name can't get in.

## Inputs

| Name | Type | Default | Description |
|------|------|---------|-------------|
| `project` | `string` | n/a (required) | Passed to `labels`. |
| `environment` | `string` | n/a (required) | `dev`, `staging`, `prod` or `live`. |
| `owner` | `string` | n/a (required) | Owner tag value. |
| `github_repository` | `string` | n/a (required) | `<owner>/<repo>`, no wildcards. |
| `github_owner_id` | `string` | `null` | Numeric owner ID. Set together with `github_repository_id`. |
| `github_repository_id` | `string` | `null` | Numeric repository ID. |
| `allowed_branches` | `list(string)` | `["main"]` | Exact branch names that may assume the role. |
| `allowed_environments` | `list(string)` | `[]` | GitHub environments that may assume the role. |
| `allow_pull_requests` | `bool` | `false` | Allow pull request runs (use only for read-only roles). |
| `create_provider` | `bool` | `true` | `false` to trust a provider the account already has. |
| `managed_policy_arns` | `list(string)` | `[]` | Policies attached to the role: its permissions. |
| `permissions_boundary` | `string` | `null` | Boundary policy ARN capping the role. |
| `max_session_duration` | `number` | `3600` | Credential lifetime in seconds, 3600 to 43200. |

## Outputs

| Name | Description |
|------|-------------|
| `provider_arn` | ARN of the GitHub OIDC provider the role trusts. |
| `role_arn` | ARN of the deploy role, for `role-to-assume`. |
| `role_name` | `<project>-<environment>-github-deploy`. |
| `allowed_subjects` | The exact subjects the trust policy accepts. |

## Example

```hcl
module "github_oidc" {
  source = "../../modules/github-oidc"

  project           = "platform"
  environment       = "dev"
  owner             = "platform-team"
  github_repository = "example-org/example-repo"

  allowed_branches     = ["main"]
  allowed_environments = ["production"]
  managed_policy_arns  = ["arn:aws:iam::123456789012:policy/platform-dev-deploy"]
}
```

The workflow side (it needs `id-token: write` so GitHub will issue the token):

```yaml
permissions:
  id-token: write
  contents: read
steps:
  - uses: aws-actions/configure-aws-credentials@v4
    with:
      role-to-assume: arn:aws:iam::123456789012:role/platform-dev-github-deploy
      aws-region: us-east-1
```

## Why it's built this way

- **One provider per account.** AWS allows a single provider per URL. If the account already has one
  (the drill account does: `live/bootstrap` creates it), set `create_provider = false` and the role trusts
  it. To bring an existing provider under this module instead, use an `import` block pointing at
  `arn:aws:iam::<account>:oidc-provider/token.actions.githubusercontent.com`, not a second provider.
- **No thumbprint.** AWS checks GitHub's certificate against its own trusted authorities, so the old
  `thumbprint_list` is no longer needed.
- **Exact subjects, no wildcards,** enforced by `validation` blocks as well as by the policy shape.
- **Pull requests are off by default.** A PR from a fork runs workflow code its author wrote; letting it
  assume a deploy role would hand out your permissions. Enable it only for a read-only role, such as one
  that runs `terraform plan`.
- **Environments for production.** A GitHub environment can require a human approval before the job
  starts, so trusting `environment:production` puts a person between a push and a deploy.
- **No permissions inside the module.** What a deploy role needs differs per stack. Keeping it out stops
  the module from becoming an admin role by default. Pass a `permissions_boundary` to cap it as well.
- **One-hour sessions.** A deploy job is minutes long, and a leaked token is worth less the shorter it lives.
- **A role must trust someone.** The module refuses to plan if no branch, environment or pull request is allowed.

## Tests

`tests/unit.tftest.hcl` (mock provider) checks the trust policy contents, exact-subject construction, the ID
form, `create_provider = false`, boundary and policy attachment, and every validation.
`tests/integration.tftest.hcl` applies the provider and role to Moto. **Moto doesn't enforce trust policies
or ship AWS-managed policies such as `ReadOnlyAccess`**, so policy attachment is covered by unit tests only
and whether GitHub can really assume the role is shown by a live drill.
