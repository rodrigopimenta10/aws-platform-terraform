# Account-level security defaults. Each resource here is a singleton: an AWS account (or account and region)
# has exactly one of each, so this module is instantiated once per account, not once per environment.

data "aws_caller_identity" "current" {}

# 1. EBS encryption by default. EBS (Elastic Block Store) is the disk service behind EC2 instances and
#    EKS nodes. The setting is per region: with it on, a volume created without an explicit encrypted flag
#    is encrypted anyway, so nobody can forget.
resource "aws_ebs_encryption_by_default" "this" {
  enabled = var.enable_ebs_encryption_by_default
}

# The default key only matters when the default is on. Null keeps the AWS-managed key (aws/ebs).
resource "aws_ebs_default_kms_key" "this" {
  count = var.enable_ebs_encryption_by_default && var.ebs_default_kms_key_arn != null ? 1 : 0

  key_arn = var.ebs_default_kms_key_arn

  depends_on = [aws_ebs_encryption_by_default.this]
}

# 2. S3 account-level Block Public Access. It overrides every bucket in the account, including buckets
#    created later and bucket policies or ACLs that try to open them up. Bucket-level settings can only be
#    stricter, never looser, once this is on.
resource "aws_s3_account_public_access_block" "this" {
  # The S3 Control API is addressed by account ID. The provider normally finds it itself; passing it
  # explicitly keeps the module working where the provider skips that lookup (the Moto tests).
  account_id = data.aws_caller_identity.current.account_id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# 3. IAM password policy. It applies to IAM users' console passwords. The platform prefers roles and OIDC
#    (no users at all), but a break-glass user or an old account would otherwise fall back on AWS's weak default.
resource "aws_iam_account_password_policy" "this" {
  minimum_password_length        = var.password_minimum_length
  require_lowercase_characters   = true
  require_uppercase_characters   = true
  require_numbers                = true
  require_symbols                = true
  allow_users_to_change_password = true
  max_password_age               = var.password_max_age_days
  password_reuse_prevention      = var.password_reuse_prevention
  hard_expiry                    = false
}
