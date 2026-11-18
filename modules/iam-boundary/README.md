# iam-boundary

A **permissions boundary** for the roles the platform creates.

An IAM **role** is an identity that gets permissions from **policies** attached to it. A permissions
**boundary** is a second policy that sets the *most* the role can ever do. The role's effective permissions
are the **intersection** of the two: an action works only if the role's own policies allow it **and** the
boundary allows it. A boundary never grants anything by itself. So even if someone attaches
`AdministratorAccess` to a role, the role stays inside the boundary.

This module creates that one managed policy. [`modules/iam-role`](../iam-role/) is the matching way to
create roles that must carry it.

## What the boundary says

| Statement | Effect | Why |
|---|---|---|
| `AllowOnlyListedServices` | Allow `<service>:*` for each of `allowed_services` | An allow-list: a role can't touch a service nobody listed |
| `DenyLongLivedIdentities` | Deny `iam:CreateUser`, `CreateAccessKey`, `CreateLoginProfile`, `UpdateLoginProfile` | Permanent credentials are what OIDC and roles replace |
| `DenyRolesWithoutThisBoundary` | Deny `iam:CreateRole` and `iam:PutRolePermissionsBoundary` unless the boundary is this policy | A role with the power to create roles could otherwise create an unbounded one and use that |
| `DenyRemovingBoundaries` | Deny `iam:DeleteRolePermissionsBoundary` | Same escape route, from the other side |
| `DenyChangesToThisBoundary` | Deny new versions, deletion and default-version changes of this policy | A role could otherwise widen its own ceiling |
| `DenyOutsideAllowedRegions` | Deny everything except global services outside `allowed_regions` | Keeps resources in the regions you watch |

An explicit **Deny** always beats an Allow, in any policy, which is why escalation is closed with Denies.

## Inputs

| Name | Type | Default | Description |
|------|------|---------|-------------|
| `project` | `string` | n/a (required) | Passed to `labels`. |
| `environment` | `string` | n/a (required) | `dev`, `staging`, `prod` or `live`. |
| `owner` | `string` | n/a (required) | Owner tag value. |
| `allowed_services` | `list(string)` | n/a (required) | Service prefixes such as `s3`, `logs`. No wildcards. |
| `allowed_regions` | `list(string)` | `["us-east-1"]` | Regions roles may call. Global services are exempt. |

## Outputs

| Name | Description |
|------|-------------|
| `policy_arn` | ARN to pass as `permissions_boundary` to every role. |
| `policy_name` | `<project>-<environment>-boundary`. |

## Example

```hcl
module "boundary" {
  source = "../../modules/iam-boundary"

  project          = "platform"
  environment      = "dev"
  owner            = "platform-team"
  allowed_services = ["s3", "logs", "kms", "ec2", "eks", "ecr"]
  allowed_regions  = ["us-east-1"]
}

module "worker_role" {
  source = "../../modules/iam-role"
  # ...
  permissions_boundary = module.boundary.policy_arn
}
```

## Why it's built this way

- **Allow-list, not a block-list.** Naming what is allowed means a new AWS service is out of reach until
  someone decides otherwise.
- **The self-referencing ARN is built from the name,** not read from the resource, because the policy
  mentions its own ARN and reading it back would be a dependency cycle.
- **`iam` is not in the default allow-list.** A role that manages IAM is a privileged role. If a caller
  adds `iam`, the Denies above still stop it creating users, keys or unbounded roles.
- **Global services are exempt from the region Deny.** IAM, STS, Route 53 and similar have no regional
  endpoint (or live in `us-east-1`), so a region Deny would break every role. `aws:RequestedRegion` also
  only governs which endpoint is called, so it is a guardrail, not a data-residency guarantee.
- **checkov skips are explained inline.** A boundary's `Allow` on `Resource = "*"` is its normal shape.
  It is the ceiling, and each role's own policy narrows it.
- **The drill role's boundary** in `live/bootstrap` is hand-written and not created by this module; roles
  in drill stacks must carry *that* one, as its `DenyRolesWithoutTheBoundary` demands.

## Tests

`tests/unit.tftest.hcl` (mock provider) checks the allow-list, each Deny, the self-referencing condition,
the region exemptions and every validation. `tests/integration.tftest.hcl` applies the policy to Moto and
checks the stored document. **Moto doesn't evaluate policies**, so the effect of the boundary on a real role
is only shown by the live drill.
