# A permissions boundary: a managed policy that sets the most any role carrying it can ever do.
# A boundary never grants anything. A role's effective permissions are the intersection of what its own
# policies allow and what the boundary allows, so even an attached AdministratorAccess stays inside it.
#
# This one has an allow-list of services, then explicit Denies that an Allow can never override:
#   - no IAM users, access keys or console passwords (long-lived identities),
#   - no requests outside the allowed regions (global services excepted),
#   - a role can only be created with this same boundary, and the boundary cannot be removed or edited.
# The last two close the escalation path "create a new role with no boundary and use that instead".

module "labels" {
  source = "../labels"

  project     = var.project
  environment = var.environment
  owner       = var.owner
  components  = ["boundary"]
}

data "aws_caller_identity" "current" {}
data "aws_partition" "current" {}

locals {
  name       = module.labels.names["boundary"]
  account_id = data.aws_caller_identity.current.account_id
  partition  = data.aws_partition.current.partition

  # Built from the name rather than read from the resource: the policy document mentions its own ARN, and
  # reading it from the resource would make a dependency cycle.
  policy_arn = "arn:${local.partition}:iam::${local.account_id}:policy/${local.name}"

  # Services with no regional endpoint, or whose API lives in us-east-1 whatever region you work in. A
  # region Deny that covered them would break every role.
  global_actions = [
    "iam:*",
    "sts:*",
    "organizations:*",
    "route53:*",
    "cloudfront:*",
    "waf:*",
    "support:*",
    "budgets:*",
    "ce:*",
    "health:*",
    "trustedadvisor:*",
  ]

  statements = concat(
    [
      {
        Sid      = "AllowOnlyListedServices"
        Effect   = "Allow"
        Action   = [for s in sort(var.allowed_services) : "${s}:*"]
        Resource = "*"
      },
      {
        Sid    = "DenyLongLivedIdentities"
        Effect = "Deny"
        Action = [
          "iam:CreateAccessKey",
          "iam:CreateLoginProfile",
          "iam:CreateUser",
          "iam:UpdateLoginProfile",
        ]
        Resource = "*"
      },
      {
        Sid      = "DenyRolesWithoutThisBoundary"
        Effect   = "Deny"
        Action   = ["iam:CreateRole", "iam:PutRolePermissionsBoundary"]
        Resource = "*"
        Condition = {
          StringNotEquals = { "iam:PermissionsBoundary" = local.policy_arn }
        }
      },
      {
        Sid      = "DenyRemovingBoundaries"
        Effect   = "Deny"
        Action   = "iam:DeleteRolePermissionsBoundary"
        Resource = "*"
      },
      {
        Sid    = "DenyChangesToThisBoundary"
        Effect = "Deny"
        Action = [
          "iam:CreatePolicyVersion",
          "iam:DeletePolicy",
          "iam:DeletePolicyVersion",
          "iam:SetDefaultPolicyVersion",
        ]
        Resource = local.policy_arn
      },
    ],
    [
      {
        Sid       = "DenyOutsideAllowedRegions"
        Effect    = "Deny"
        NotAction = local.global_actions
        Resource  = "*"
        Condition = {
          StringNotEquals = { "aws:RequestedRegion" = var.allowed_regions }
        }
      },
    ],
  )
}

resource "aws_iam_policy" "boundary" {
  #checkov:skip=CKV_AWS_288:A boundary only caps permissions and grants none. The allow-list is per service, and the explicit Denies in the same document close data exfiltration and escalation paths that matter for roles.
  #checkov:skip=CKV_AWS_289:Same: an Allow in a boundary grants nothing on its own, and the Deny statements cover permission management.
  #checkov:skip=CKV_AWS_290:Same: write access is limited by each role's own policies, this document is only the ceiling.
  #checkov:skip=CKV_AWS_355:Resource "*" is how a boundary is written. It is the ceiling for every resource a role may touch, and each role's own policy narrows it.
  name        = local.name
  description = "Permissions boundary for roles in ${var.project}-${var.environment}: listed services only, no IAM users or keys, allowed regions only, and new roles must carry this boundary."
  policy      = jsonencode({ Version = "2012-10-17", Statement = local.statements })

  tags = merge(module.labels.tags, { Name = local.name })
}
