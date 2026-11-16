# A customer-managed KMS key with yearly rotation and a key policy that keeps three jobs apart:
# the account's IAM policies (delegation), administrators (manage, cannot use), and users (use, cannot manage).
# AWS services get access only through explicit grants, optionally limited by encryption context.
# One module call makes one key, so each workload gets its own key and its own blast radius.

module "labels" {
  source = "../labels"

  project     = var.project
  environment = var.environment
  owner       = var.owner
  components  = [var.purpose]
}

data "aws_caller_identity" "current" {}
data "aws_partition" "current" {}

locals {
  name       = module.labels.names[var.purpose]
  account_id = data.aws_caller_identity.current.account_id
  partition  = data.aws_partition.current.partition

  admin_actions = [
    "kms:CancelKeyDeletion",
    "kms:Create*",
    "kms:Delete*",
    "kms:Describe*",
    "kms:Disable*",
    "kms:Enable*",
    "kms:Get*",
    "kms:List*",
    "kms:Put*",
    "kms:Revoke*",
    "kms:ScheduleKeyDeletion",
    "kms:TagResource",
    "kms:UntagResource",
    "kms:Update*",
  ]

  use_actions = [
    "kms:Decrypt",
    "kms:DescribeKey",
    "kms:Encrypt",
    "kms:GenerateDataKey*",
    "kms:ReEncrypt*",
  ]

  statements = concat(
    [
      {
        # Lets IAM policies grant access. Without it a key policy would have to name every principal itself.
        Sid       = "EnableIAMPolicies"
        Effect    = "Allow"
        Principal = { AWS = "arn:${local.partition}:iam::${local.account_id}:root" }
        Action    = "kms:*"
        Resource  = "*"
      },
    ],
    length(var.key_administrator_arns) == 0 ? [] : [
      {
        Sid       = "KeyAdministratorsManageButCannotUse"
        Effect    = "Allow"
        Principal = { AWS = var.key_administrator_arns }
        Action    = local.admin_actions
        Resource  = "*"
      },
    ],
    length(var.key_user_arns) == 0 ? [] : [
      {
        Sid       = "KeyUsersEncryptAndDecrypt"
        Effect    = "Allow"
        Principal = { AWS = var.key_user_arns }
        Action    = local.use_actions
        Resource  = "*"
      },
    ],
    [
      for k, g in var.service_grants : merge(
        {
          Sid       = "Service${k}"
          Effect    = "Allow"
          Principal = { Service = g.service }
          Action    = local.use_actions
          Resource  = "*"
        },
        length(g.encryption_context) == 0 ? {} : {
          Condition = {
            StringEquals = { for ck, cv in g.encryption_context : "kms:EncryptionContext:${ck}" => cv }
          }
        },
      )
    ],
  )
}

resource "aws_kms_key" "this" {
  description             = var.description
  enable_key_rotation     = true
  rotation_period_in_days = var.rotation_period_in_days
  deletion_window_in_days = var.deletion_window_in_days

  # Resource "*" in a key policy means "this key" and cannot name anything else.
  #checkov:skip=CKV_AWS_109:Key policy resource "*" means this key only; the root statement is required so IAM can delegate access
  #checkov:skip=CKV_AWS_111:Key policy resource "*" means this key only; the root statement is required so IAM can delegate access
  #checkov:skip=CKV_AWS_356:Key policy resource "*" means this key only; the root statement is required so IAM can delegate access
  policy = jsonencode({
    Version   = "2012-10-17"
    Statement = local.statements
  })

  tags = merge(module.labels.tags, { Name = local.name })
}

resource "aws_kms_alias" "this" {
  name          = "alias/${local.name}"
  target_key_id = aws_kms_key.this.key_id
}
