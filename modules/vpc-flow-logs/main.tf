# VPC flow logs: a record of the network connections (source, destination, port, protocol, accepted or
# rejected) that cross the VPC's network interfaces. They do not contain packet contents. Used to answer
# "who talked to whom" and "what did my security group block" after the fact.
#
# Records go to a CloudWatch Logs log group, encrypted with its own customer-managed KMS key. The VPC flow
# logs service writes them by assuming an IAM role that can only write to that one log group.

module "labels" {
  source = "../labels"

  project     = var.project
  environment = var.environment
  owner       = var.owner
  components  = ["flow-logs"]
}

data "aws_caller_identity" "current" {}
data "aws_partition" "current" {}
data "aws_region" "current" {}

locals {
  name       = module.labels.names["flow-logs"]
  account_id = data.aws_caller_identity.current.account_id
  partition  = data.aws_partition.current.partition
  region     = data.aws_region.current.region

  log_group_name = "/aws/vpc/flow-logs/${local.name}"

  # Built from its documented format instead of read from the log group. The key policy must name the log
  # group, and the log group names the key, so reading the ARN from the resource would be a cycle.
  log_group_arn = "arn:${local.partition}:logs:${local.region}:${local.account_id}:log-group:${local.log_group_name}"
}

# ---------------------------------------------------------------------------------------------
# Encryption key
# ---------------------------------------------------------------------------------------------
resource "aws_kms_key" "this" {
  description             = "Encrypts the VPC flow log group ${local.log_group_name}"
  enable_key_rotation     = true
  deletion_window_in_days = var.kms_deletion_window_in_days

  # Resource "*" in a key policy means "this key" and cannot name anything else.
  #checkov:skip=CKV_AWS_109:Key policy resource "*" means this key only; the root statement is required so IAM can delegate access
  #checkov:skip=CKV_AWS_111:Key policy resource "*" means this key only; the root statement is required so IAM can delegate access
  #checkov:skip=CKV_AWS_356:Key policy resource "*" means this key only; the root statement is required so IAM can delegate access
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        # Lets IAM policies grant access. Without it nobody could ever be given use of the key.
        Sid       = "EnableIAMPolicies"
        Effect    = "Allow"
        Principal = { AWS = "arn:${local.partition}:iam::${local.account_id}:root" }
        Action    = "kms:*"
        Resource  = "*"
      },
      {
        # CloudWatch Logs encrypts and decrypts with the key, but only for this log group: the encryption
        # context carries the log group's ARN, so the same service cannot use the key for any other group.
        Sid       = "AllowCloudWatchLogsForThisLogGroupOnly"
        Effect    = "Allow"
        Principal = { Service = "logs.${local.region}.amazonaws.com" }
        Action = [
          "kms:Decrypt*",
          "kms:Describe*",
          "kms:Encrypt*",
          "kms:GenerateDataKey*",
          "kms:ReEncrypt*",
        ]
        Resource = "*"
        Condition = {
          ArnEquals = { "kms:EncryptionContext:aws:logs:arn" = local.log_group_arn }
        }
      },
    ]
  })

  tags = module.labels.tags
}

resource "aws_kms_alias" "this" {
  name          = "alias/${local.name}"
  target_key_id = aws_kms_key.this.key_id
}

# ---------------------------------------------------------------------------------------------
# Log group
# ---------------------------------------------------------------------------------------------
resource "aws_cloudwatch_log_group" "this" {
  name              = local.log_group_name
  retention_in_days = var.retention_in_days
  kms_key_id        = aws_kms_key.this.arn

  tags = module.labels.tags
}

# ---------------------------------------------------------------------------------------------
# Role the flow logs service assumes
# ---------------------------------------------------------------------------------------------
resource "aws_iam_role" "this" {
  name                 = "${local.name}-role"
  description          = "Assumed by the VPC flow logs service to write to ${local.log_group_name}."
  permissions_boundary = var.permissions_boundary

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "vpc-flow-logs.amazonaws.com" }
      Action    = "sts:AssumeRole"
      # Confused-deputy protection: only flow logs from this account may use the role.
      Condition = {
        StringEquals = { "aws:SourceAccount" = local.account_id }
        ArnLike      = { "aws:SourceArn" = "arn:${local.partition}:ec2:${local.region}:${local.account_id}:vpc-flow-log/*" }
      }
    }]
  })

  tags = module.labels.tags
}

resource "aws_iam_role_policy" "this" {
  name = "write-flow-logs"
  role = aws_iam_role.this.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Sid    = "WriteToTheFlowLogGroupOnly"
      Effect = "Allow"
      Action = [
        "logs:CreateLogStream",
        "logs:DescribeLogStreams",
        "logs:PutLogEvents",
      ]
      Resource = [local.log_group_arn, "${local.log_group_arn}:*"]
    }]
  })
}

# ---------------------------------------------------------------------------------------------
# The flow log itself
# ---------------------------------------------------------------------------------------------
resource "aws_flow_log" "this" {
  vpc_id                   = var.vpc_id
  traffic_type             = var.traffic_type
  log_destination_type     = "cloud-watch-logs"
  log_destination          = aws_cloudwatch_log_group.this.arn
  iam_role_arn             = aws_iam_role.this.arn
  max_aggregation_interval = var.max_aggregation_interval

  tags = merge(module.labels.tags, { Name = local.name })
}
