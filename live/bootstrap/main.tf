# One-time stack for the live drill, applied by hand by an account admin (never by an agent or a workflow).
# It creates what the drill workflow needs before it can run at all:
#   1. an S3 bucket (plus KMS key) for the drill stacks' Terraform state, via modules/state-backend,
#   2. the GitHub Actions OIDC identity provider, so GitHub can hand the workflow short-lived AWS
#      credentials instead of us storing access keys in GitHub,
#   3. the role platform-live-drill, which only the aws-live environment of this repo can assume.
# README.md explains the permission trade-off and the exact apply and state-migration steps.

provider "aws" {
  region = var.region

  default_tags {
    tags = module.labels.tags
  }
}

module "labels" {
  source = "../../modules/labels"

  project     = "platform"
  environment = "live"
  owner       = var.owner
  components  = ["drill"]
}

module "state_backend" {
  source = "../../modules/state-backend"

  project     = "platform"
  environment = "live"
  owner       = var.owner
}

data "aws_caller_identity" "current" {}
data "aws_partition" "current" {}

locals {
  account_id = data.aws_caller_identity.current.account_id
  partition  = data.aws_partition.current.partition

  github_oidc_host = "token.actions.githubusercontent.com"
  role_name        = module.labels.names["drill"]

  # GitHub's default subject claim for a job that runs in an environment:
  # repo:<owner>/<repo>:environment:<name>. Branch, pull request and other-repo tokens all carry a
  # different subject, so they cannot match.
  # GitHub's subject for this repository includes the owner's and the repository's numeric IDs:
  # repo:<owner>@<owner id>/<repo>@<repo id>:environment:<name>. Seen in CloudTrail on the first drill
  # (2026-11-12): a role expecting the plain repo:<owner>/<repo>:... form was refused with AccessDenied.
  # The IDs never change, so a renamed or re-created repository with the same name cannot match.
  github_owner = split("/", var.github_repository)[0]
  github_name  = split("/", var.github_repository)[1]
  oidc_subject = "repo:${local.github_owner}@${var.github_owner_id}/${local.github_name}@${var.github_repository_id}:environment:${var.github_environment}"

  # ARNs are built from their documented formats (rather than read from the resources) so the policies
  # are fully known at plan time and the unit tests can inspect them.
  oidc_provider_arn = "arn:${local.partition}:iam::${local.account_id}:oidc-provider/${local.github_oidc_host}"
  role_arn          = "arn:${local.partition}:iam::${local.account_id}:role/${local.role_name}"
  budgets_role_arn  = "arn:${local.partition}:iam::${local.account_id}:role/${local.role_name}-budgets-action"

  # Services exempt from the region guardrail. aws:RequestedRegion is the region of the endpoint a request
  # is sent to. Global services with a single endpoint (IAM, CloudFront, Route 53, Support, Budgets, Cost
  # Explorer) are always called in us-east-1, so with region = us-east-1 they pass anyway; listing them
  # keeps the policy correct if the drill region ever changes. STS also has regional endpoints, so a
  # client configured for another region would otherwise be unable even to call GetCallerIdentity.
  # Sources:
  #   https://docs.aws.amazon.com/IAM/latest/UserGuide/reference_policies_condition-keys.html#condition-keys-requestedregion
  #   https://docs.aws.amazon.com/IAM/latest/UserGuide/reference_policies_examples_aws_deny-requested-region.html
  # organizations:* and account:* are not listed because the next statement denies them everywhere.
  region_exempt_actions = [
    "budgets:*",
    "ce:*",
    "cloudfront:*",
    "iam:*",
    "route53:*",
    "sts:*",
    "support:*",
  ]

  boundary_name     = "${local.role_name}-boundary"
  boundary_arn      = "arn:${local.partition}:iam::${local.account_id}:policy/${local.boundary_name}"
  stop_policy_name  = "${local.role_name}-stop"
  stop_policy_arn   = "arn:${local.partition}:iam::${local.account_id}:policy/${local.stop_policy_name}"
  guard_budget_name = "${local.role_name}-guard"
  guard_budget_arn  = "arn:${local.partition}:budgets::${local.account_id}:budget/${local.guard_budget_name}"

  # The only services a drill may call. Everything else is denied, so a bad commit can't start, say,
  # SageMaker, RDS or a Marketplace subscription. Adding a service is a bootstrap change by an admin.
  # Deliberately absent: servicequotas (raising the 5 vCPU / 0 GPU account limits), support (quota
  # increase cases), savingsplans, aws-marketplace, organizations, account, billing.
  allowed_services = [
    "acm:*",
    "application-autoscaling:*",
    "autoscaling:*",
    "budgets:*",
    "cloudwatch:*",
    "dynamodb:*",
    "ec2:*",
    "ec2messages:*",
    "ecr:*",
    "eks:*",
    "eks-auth:*",
    "elasticloadbalancing:*",
    "events:*",
    "iam:*",
    "kms:*",
    "lambda:*",
    "logs:*",
    "apigateway:*",
    "pricing:*",
    "resource-groups:*",
    "route53:*",
    "s3:*",
    "secretsmanager:*",
    "sns:*",
    "sqs:*",
    "ssm:*",
    "ssmmessages:*",
    "sts:*",
    "tag:*",
    "xray:*",
  ]

  # Statements shared by the role's inline guardrails and the permissions boundary, so every role a
  # drill creates is held to the same limits as the drill role itself.
  shared_guard_statements = [
    {
      Sid       = "DenyServicesDrillsDoNotUse"
      Effect    = "Deny"
      NotAction = local.allowed_services
      Resource  = "*"
    },
    {
      Sid       = "DenyOutsideDrillRegion"
      Effect    = "Deny"
      NotAction = local.region_exempt_actions
      Resource  = "*"
      Condition = {
        StringNotEquals = { "aws:RequestedRegion" = [var.region] }
      }
    },
    {
      # Small burstable types only. Node groups launch through the Auto Scaling service-linked role,
      # which this does not bind; the account's 5 vCPU on-demand quota and live/plan-gate.sh cover those.
      Sid      = "DenyLargeInstanceTypes"
      Effect   = "Deny"
      Action   = "ec2:RunInstances"
      Resource = "arn:${local.partition}:ec2:*:*:instance/*"
      Condition = {
        StringNotLike = { "ec2:InstanceType" = var.allowed_instance_types }
      }
    },
    {
      Sid    = "DenyLongTermPurchasesAndDedicatedCapacity"
      Effect = "Deny"
      Action = [
        "ec2:AllocateHosts",
        "ec2:CreateCapacityReservation",
        "ec2:CreateCapacityReservationFleet",
        "ec2:PurchaseCapacityBlock",
        "ec2:PurchaseHostReservation",
        "ec2:PurchaseReservedInstancesOffering",
        "ec2:PurchaseScheduledInstances",
      ]
      Resource = "*"
    },
    {
      Sid    = "DenyLongLivedIdentitiesAndAccountChanges"
      Effect = "Deny"
      Action = [
        "account:*",
        "iam:CreateAccessKey",
        "iam:CreateLoginProfile",
        "iam:CreateUser",
        "iam:UpdateLoginProfile",
        "organizations:*",
      ]
      Resource = "*"
    },
    {
      # Closes the escalation path: without this, a drill could create a role with AdministratorAccess and
      # no guardrails, assume it, and do anything. Every new role must carry this boundary, which caps it
      # at these same limits whatever policies are attached to it.
      Sid      = "DenyRolesWithoutTheBoundary"
      Effect   = "Deny"
      Action   = ["iam:CreateRole", "iam:PutRolePermissionsBoundary"]
      Resource = "*"
      Condition = {
        StringNotEquals = { "iam:PermissionsBoundary" = local.boundary_arn }
      }
    },
    {
      Sid      = "DenyRemovingBoundaries"
      Effect   = "Deny"
      Action   = "iam:DeleteRolePermissionsBoundary"
      Resource = "*"
    },
    {
      Sid    = "DenyChangesToGuardPolicies"
      Effect = "Deny"
      Action = [
        "iam:CreatePolicyVersion",
        "iam:DeletePolicy",
        "iam:DeletePolicyVersion",
        "iam:SetDefaultPolicyVersion",
        "iam:TagPolicy",
        "iam:UntagPolicy",
      ]
      Resource = [local.boundary_arn, local.stop_policy_arn]
    },
    {
      # Budgets is allowed (roadmap M6.2 creates one), but not the guard budget or its action, and not
      # budgets outside the platform-live-* names (such as the account owner's own).
      Sid    = "DenyChangesToGuardBudget"
      Effect = "Deny"
      Action = [
        "budgets:CreateBudgetAction",
        "budgets:DeleteBudget",
        "budgets:DeleteBudgetAction",
        "budgets:ExecuteBudgetAction",
        "budgets:ModifyBudget",
        "budgets:UpdateBudgetAction",
      ]
      Resource = [local.guard_budget_arn, "${local.guard_budget_arn}/action/*"]
    },
    {
      Sid         = "DenyChangesToOtherBudgets"
      Effect      = "Deny"
      Action      = ["budgets:CreateBudgetAction", "budgets:DeleteBudget", "budgets:DeleteBudgetAction", "budgets:ExecuteBudgetAction", "budgets:ModifyBudget", "budgets:UpdateBudgetAction"]
      NotResource = ["arn:${local.partition}:budgets::${local.account_id}:budget/platform-live-*"]
    },
  ]

  trust_policy = {
    Version = "2012-10-17"
    Statement = [{
      Sid       = "GitHubAwsLiveEnvironmentOnly"
      Effect    = "Allow"
      Principal = { Federated = local.oidc_provider_arn }
      Action    = "sts:AssumeRoleWithWebIdentity"
      Condition = {
        StringEquals = {
          "token.actions.githubusercontent.com:aud" = "sts.amazonaws.com"
          "token.actions.githubusercontent.com:sub" = local.oidc_subject
        }
      }
    }]
  }

  guardrails_policy = {
    Version = "2012-10-17"
    Statement = concat(local.shared_guard_statements, [
      {
        # aws:RequestedRegion only controls which endpoint is called. s3:CreateBucket sent to the us-east-1
        # endpoint can still create a bucket in another region through its LocationConstraint, so that
        # case is denied separately (same IAM page, the note under aws:RequestedRegion). A us-east-1
        # bucket has no LocationConstraint at all: StringLike on a missing key is false, so it passes.
        Sid      = "DenyBucketsOutsideDrillRegion"
        Effect   = "Deny"
        Action   = "s3:CreateBucket"
        Resource = "*"
        Condition = {
          StringLike      = { "s3:LocationConstraint" = "*" }
          StringNotEquals = { "s3:LocationConstraint" = [var.region] }
        }
      },
      {
        # The role cannot widen its own permissions, change who may assume it, or remove these guardrails,
        # and cannot tamper with the role AWS Budgets uses to stop it.
        Sid    = "DenyChangesToThisRole"
        Effect = "Deny"
        Action = [
          "iam:AttachRolePolicy",
          "iam:DeleteRole",
          "iam:DeleteRolePermissionsBoundary",
          "iam:DeleteRolePolicy",
          "iam:DetachRolePolicy",
          "iam:PassRole",
          "iam:PutRolePermissionsBoundary",
          "iam:PutRolePolicy",
          "iam:TagRole",
          "iam:UntagRole",
          "iam:UpdateAssumeRolePolicy",
          "iam:UpdateRole",
          "iam:UpdateRoleDescription",
        ]
        Resource = [local.role_arn, local.budgets_role_arn]
      },
      {
        Sid    = "DenyChangesToGitHubOidcProvider"
        Effect = "Deny"
        Action = [
          "iam:AddClientIDToOpenIDConnectProvider",
          "iam:DeleteOpenIDConnectProvider",
          "iam:RemoveClientIDFromOpenIDConnectProvider",
          "iam:TagOpenIDConnectProvider",
          "iam:UntagOpenIDConnectProvider",
          "iam:UpdateOpenIDConnectProviderThumbprint",
        ]
        Resource = local.oidc_provider_arn
      },
      {
        # The drills read and write their own state under live/ in this bucket. They must not be able to
        # delete the bucket, weaken its settings, erase old versions, or touch this stack's own state.
        Sid    = "DenyChangesToStateBucket"
        Effect = "Deny"
        Action = [
          "s3:DeleteBucket",
          "s3:DeleteBucketPolicy",
          "s3:PutBucketAcl",
          "s3:PutBucketOwnershipControls",
          "s3:PutBucketPolicy",
          "s3:PutBucketPublicAccessBlock",
          "s3:PutBucketVersioning",
          "s3:PutEncryptionConfiguration",
          "s3:PutLifecycleConfiguration",
        ]
        Resource = module.state_backend.bucket_arn
      },
      {
        Sid      = "DenyErasingStateHistory"
        Effect   = "Deny"
        Action   = "s3:DeleteObjectVersion"
        Resource = "${module.state_backend.bucket_arn}/*"
      },
      {
        Sid      = "DenyWritesToBootstrapState"
        Effect   = "Deny"
        Action   = ["s3:DeleteObject", "s3:PutObject"]
        Resource = "${module.state_backend.bucket_arn}/bootstrap/*"
      },
      {
        Sid    = "DenyDisablingStateKey"
        Effect = "Deny"
        Action = [
          "kms:DisableKey",
          "kms:DisableKeyRotation",
          "kms:PutKeyPolicy",
          "kms:ScheduleKeyDeletion",
        ]
        Resource = module.state_backend.kms_key_arn
      },
    ])
  }

  # The ceiling for every role a drill creates (and for the drill role itself): allow everything, then the
  # shared denies. A boundary never grants anything; the effective permissions are the intersection.
  boundary_policy = {
    Version = "2012-10-17"
    Statement = concat([
      {
        Sid      = "AllowWithinTheLimitsBelow"
        Effect   = "Allow"
        Action   = "*"
        Resource = "*"
      }],
      local.shared_guard_statements,
    )
  }
}

# ---------------------------------------------------------------------------------------------
# GitHub Actions OIDC identity provider
# ---------------------------------------------------------------------------------------------
# AWS allows one provider per URL in an account. M2.2 (modules/github-oidc) must take this one over with
# import/moved blocks instead of creating a second; see ROADMAP.md.
resource "aws_iam_openid_connect_provider" "github" {
  url = "https://${local.github_oidc_host}"

  # The audience GitHub puts in tokens requested by aws-actions/configure-aws-credentials.
  client_id_list = ["sts.amazonaws.com"]

  # No thumbprint_list: IAM verifies GitHub's TLS certificate against its own library of trusted root
  # CAs, and retrieves a thumbprint itself when none is given.
  # https://docs.aws.amazon.com/IAM/latest/UserGuide/id_roles_providers_create_oidc_verify-thumbprint.html
}

# ---------------------------------------------------------------------------------------------
# The drill role
# ---------------------------------------------------------------------------------------------
resource "aws_iam_role" "drill" {
  #checkov:skip=CKV_AWS_393:False positive. The rule only recognises the subject form repo:<owner>/<repo>:..., but GitHub sends this repository's subject with numeric owner and repository IDs (repo:<owner>@<id>/<repo>@<id>:environment:aws-live, seen in CloudTrail on 2026-11-12). The condition is still one exact StringEquals on repository and environment, plus the audience. See live/bootstrap/README.md.
  name                 = local.role_name
  description          = "Assumed only by the ${var.github_environment} environment of ${var.github_repository} to apply and destroy live drill stacks."
  assume_role_policy   = jsonencode(local.trust_policy)
  max_session_duration = var.max_session_duration
  permissions_boundary = aws_iam_policy.boundary.arn

  # The trust policy names the provider by its ARN string, so make the ordering explicit.
  depends_on = [aws_iam_openid_connect_provider.github]
}

# Drill stacks will grow from a VPC to EKS, IAM roles, Lambda and more, and each milestone would otherwise
# need a hand-edited policy before it could be drilled. The trade-off (broad allow, explicit denies, a
# human approval on every assumption) is written up in README.md.
resource "aws_iam_role_policy_attachment" "administrator" {
  #checkov:skip=CKV_AWS_274:Deliberate. The drill applies every future milestone (EKS, IAM, Lambda...); the role is assumable only from the aws-live GitHub environment after a human approval, sessions last 1 hour, and the inline guardrails policy denies other regions, long-lived identities and changes to the role, OIDC provider and state bucket. See live/bootstrap/README.md.
  role       = aws_iam_role.drill.name
  policy_arn = "arn:${local.partition}:iam::aws:policy/AdministratorAccess"
}

# An explicit Deny always wins over an Allow, so these limits hold whatever AdministratorAccess allows.
resource "aws_iam_role_policy" "guardrails" {
  name   = "live-drill-guardrails"
  role   = aws_iam_role.drill.id
  policy = jsonencode(local.guardrails_policy)
}

# ---------------------------------------------------------------------------------------------
# Permissions boundary for every role a drill creates
# ---------------------------------------------------------------------------------------------
# Drill stacks pass this ARN to modules that create IAM roles (TF_VAR_permissions_boundary_arn, set by the
# workflow). A role created without it is refused by DenyRolesWithoutTheBoundary.
resource "aws_iam_policy" "boundary" {
  #checkov:skip=CKV_AWS_288:A permissions boundary only caps permissions, it grants none; Allow * is the standard boundary shape, narrowed by the explicit denies in the same document.
  #checkov:skip=CKV_AWS_289:Same: a boundary's Allow * grants nothing on its own.
  #checkov:skip=CKV_AWS_290:Same: a boundary's Allow * grants nothing on its own.
  #checkov:skip=CKV_AWS_355:Same: a boundary's Allow * grants nothing on its own.
  #checkov:skip=CKV_AWS_286:Same: a boundary's Allow * grants nothing on its own.
  #checkov:skip=CKV_AWS_287:Same: a boundary's Allow * grants nothing on its own.
  #checkov:skip=CKV_AWS_62:Same: a boundary's Allow * grants nothing on its own.
  #checkov:skip=CKV_AWS_63:Same: a boundary's Allow * grants nothing on its own.
  #checkov:skip=CKV2_AWS_40:Same: a boundary's Allow * grants nothing on its own.
  name        = local.boundary_name
  description = "Ceiling for live-drill roles: drill region, allowed services, small instances, no long-lived identities, no escaping this boundary."
  policy      = jsonencode(local.boundary_policy)
}

# ---------------------------------------------------------------------------------------------
# Hard stop on spend: a budget action that attaches a deny-all policy to the drill role
# ---------------------------------------------------------------------------------------------
# Budgets reads billing data a few times a day, so this is a backstop measured in hours, not a meter.
# The faster controls are the one-at-a-time drills, the destroy in the same job, the hourly reaper and the
# 5 vCPU account quota. To lift the stop: detach platform-live-drill-stop from the role, as an admin.
resource "aws_iam_policy" "stop" {
  name        = local.stop_policy_name
  description = "Attached to platform-live-drill by the guard budget's action when spend passes the limit. Denies everything."
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Sid      = "DenyEverything"
      Effect   = "Deny"
      Action   = "*"
      Resource = "*"
    }]
  })
}

resource "aws_iam_role" "budgets_action" {
  name        = "${local.role_name}-budgets-action"
  description = "Lets AWS Budgets attach the stop policy to platform-live-drill when the guard budget is exceeded."
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      # Budgets checks it can assume the role while the action is created, before the action has an ARN,
      # so the condition is on the account only (an ArnLike on the action ARN was refused, 2026-11-13).
      Effect    = "Allow"
      Principal = { Service = ["budgets.amazonaws.com", "actions.budgets.amazonaws.com"] }
      Action    = "sts:AssumeRole"
      Condition = {
        StringEquals = { "aws:SourceAccount" = local.account_id }
      }
    }]
  })
}

resource "aws_iam_role_policy" "budgets_action" {
  name = "attach-stop-policy"
  role = aws_iam_role.budgets_action.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Sid      = "AttachOnlyTheStopPolicyToTheDrillRole"
      Effect   = "Allow"
      Action   = ["iam:AttachRolePolicy", "iam:DetachRolePolicy"]
      Resource = local.role_arn
      Condition = {
        ArnEquals = { "iam:PolicyARN" = local.stop_policy_arn }
      }
    }]
  })
}

resource "aws_budgets_budget" "guard" {
  name         = local.guard_budget_name
  budget_type  = "COST"
  limit_amount = tostring(var.guard_budget_usd)
  limit_unit   = "USD"
  time_unit    = "MONTHLY"

  notification {
    comparison_operator        = "GREATER_THAN"
    threshold                  = 50
    threshold_type             = "PERCENTAGE"
    notification_type          = "ACTUAL"
    subscriber_email_addresses = [var.alert_email]
  }
}

resource "aws_budgets_budget_action" "stop_drills" {
  budget_name        = aws_budgets_budget.guard.name
  action_type        = "APPLY_IAM_POLICY"
  approval_model     = "AUTOMATIC"
  notification_type  = "ACTUAL"
  execution_role_arn = aws_iam_role.budgets_action.arn

  action_threshold {
    action_threshold_type  = "PERCENTAGE"
    action_threshold_value = 100
  }

  definition {
    iam_action_definition {
      policy_arn = aws_iam_policy.stop.arn
      roles      = [aws_iam_role.drill.name]
    }
  }

  subscriber {
    address           = var.alert_email
    subscription_type = "EMAIL"
  }
}
