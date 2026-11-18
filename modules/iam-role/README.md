# iam-role

An IAM role that **refuses to be created without a permissions boundary**.

A **permissions boundary** ([`modules/iam-boundary`](../iam-boundary/)) caps what a role can do whatever
policies are attached to it. It only helps if every role has one, and Terraform cannot stop someone writing
a bare `aws_iam_role`. This module is the platform's standard way to create a role: a `precondition` on
the role fails the plan, before anything reaches AWS, when `permissions_boundary` is `null`.

There are two layers. This module is the early, friendly one (a clear error at `terraform plan`). The
boundary policy's own `DenyRolesWithoutThisBoundary` is the hard one, enforced by AWS itself against any
role creation, Terraform or not.

## Inputs

| Name | Type | Default | Description |
|------|------|---------|-------------|
| `project` | `string` | n/a (required) | Passed to `labels`. |
| `environment` | `string` | n/a (required) | `dev`, `staging`, `prod` or `live`. |
| `owner` | `string` | n/a (required) | Owner tag value. |
| `name` | `string` | n/a (required) | Component name: the role is `<project>-<environment>-<name>`. |
| `description` | `string` | n/a (required) | What the role is for. |
| `assume_role_policy` | `string` | n/a (required) | Trust policy JSON: who may assume the role. |
| `permissions_boundary` | `string` | `null` | Boundary ARN. `null` fails the precondition. |
| `managed_policy_arns` | `list(string)` | `[]` | Policies attached to the role. |
| `max_session_duration` | `number` | `3600` | Credential lifetime in seconds, 3600 to 43200. |

## Outputs

| Name | Description |
|------|-------------|
| `role_arn` | ARN of the role. |
| `role_name` | `<project>-<environment>-<name>`. |
| `permissions_boundary` | The boundary ARN the role carries. |

## Example

```hcl
module "worker" {
  source = "../../modules/iam-role"

  project     = "platform"
  environment = "dev"
  owner       = "platform-team"
  name        = "worker"
  description = "Runs the example worker"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "ec2.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })

  permissions_boundary = module.boundary.policy_arn
  managed_policy_arns  = ["arn:aws:iam::aws:policy/ReadOnlyAccess"]
}
```

Leave `permissions_boundary` out and the plan stops with: `Role platform-dev-worker has no permissions
boundary...`.

## Why it's built this way

- **A `precondition`, not just a required variable.** The variable is optional (`null`) so the error can
  name the role and explain the risk, instead of Terraform's generic "no value for required variable".
  `null` also lets a caller pass a boundary that is itself computed.
- **No "skip the boundary" switch.** An escape hatch would be the first thing used under pressure.
- **Permissions stay with the caller.** Like `github-oidc`, the module grants nothing itself; what a role
  may do differs per use, and the boundary caps it.
- **Role names go through `labels`,** so they follow the naming convention in ADR 0002.

## Tests

`tests/unit.tftest.hcl` (mock provider) checks the boundary is set, that a role **without** one is
rejected (`expect_failures` on the role's precondition), policy attachment and each validation.
`tests/integration.tftest.hcl` applies the role to Moto and checks the stored boundary. Moto does not
evaluate boundaries, so their effect is a live-drill matter.
