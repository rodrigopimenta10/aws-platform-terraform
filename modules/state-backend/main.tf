# Remote state storage for Terraform: one S3 bucket plus a customer-managed KMS key.
# Locking uses S3 native lock files (`use_lockfile = true` in the backend block), so no DynamoDB table
# is needed. See docs/adr/0003-s3-native-state-locking.md.

module "labels" {
  source = "../labels"

  project     = var.project
  environment = var.environment
  owner       = var.owner
  components  = ["tfstate"]
  extra_tags  = var.extra_tags
}

data "aws_caller_identity" "current" {}
data "aws_region" "current" {}

locals {
  # S3 bucket names are global across every AWS account, so the account ID and region make the name
  # unique and tell you where it lives. Longest case is 25 + 8 + 13 + 15 characters, under the 63 limit.
  bucket_name = "${module.labels.names["tfstate"]}-${data.aws_caller_identity.current.account_id}-${data.aws_region.current.region}"
}

# ---------------------------------------------------------------------------------------------
# Encryption key
# ---------------------------------------------------------------------------------------------
resource "aws_kms_key" "state" {
  description             = "Encrypts Terraform state in ${local.bucket_name}"
  enable_key_rotation     = true
  deletion_window_in_days = var.kms_deletion_window_in_days

  # The default-style key policy: the account root may delegate access through IAM policies. Without
  # this statement nobody could ever be granted use of the key. "Resource": "*" in a key policy
  # means "this key", it cannot refer to any other resource.
  #checkov:skip=CKV_AWS_109:Key policy resource "*" means this key only; the root statement is required so IAM can delegate access
  #checkov:skip=CKV_AWS_111:Key policy resource "*" means this key only; the root statement is required so IAM can delegate access
  #checkov:skip=CKV_AWS_356:Key policy resource "*" means this key only; the root statement is required so IAM can delegate access
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Sid       = "EnableIAMPolicies"
      Effect    = "Allow"
      Principal = { AWS = "arn:aws:iam::${data.aws_caller_identity.current.account_id}:root" }
      Action    = "kms:*"
      Resource  = "*"
    }]
  })

  tags = module.labels.tags
}

resource "aws_kms_alias" "state" {
  name          = "alias/${module.labels.names["tfstate"]}"
  target_key_id = aws_kms_key.state.key_id
}

# ---------------------------------------------------------------------------------------------
# State bucket
# ---------------------------------------------------------------------------------------------
resource "aws_s3_bucket" "state" {
  #checkov:skip=CKV_AWS_18:Access logging needs a second log bucket; planned with the logging work, state access is already recorded by CloudTrail in a real account
  #checkov:skip=CKV_AWS_144:Cross-region replication doubles cost and is out of scope for a single-region learning platform
  #checkov:skip=CKV2_AWS_62:No event consumers exist for state files
  bucket        = local.bucket_name
  force_destroy = var.force_destroy

  tags = module.labels.tags
}

# Versioning keeps every previous state file, so a corrupt or wrong apply can be rolled back.
resource "aws_s3_bucket_versioning" "state" {
  bucket = aws_s3_bucket.state.id

  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "state" {
  bucket = aws_s3_bucket.state.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm     = "aws:kms"
      kms_master_key_id = aws_kms_key.state.arn
    }
    # Bucket keys cut KMS request volume (and cost) by reusing a bucket-level data key.
    bucket_key_enabled = true
  }
}

resource "aws_s3_bucket_public_access_block" "state" {
  bucket = aws_s3_bucket.state.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# BucketOwnerEnforced switches ACLs (an old per-object permission system) off entirely, so access is
# controlled only by IAM and the bucket policy.
resource "aws_s3_bucket_ownership_controls" "state" {
  bucket = aws_s3_bucket.state.id

  rule {
    object_ownership = "BucketOwnerEnforced"
  }
}

resource "aws_s3_bucket_policy" "state" {
  bucket = aws_s3_bucket.state.id

  # The ARNs are built from the bucket name (known at plan time) so the policy can be unit tested.
  # Public access block must exist first, otherwise the policy can race with it.
  depends_on = [aws_s3_bucket_public_access_block.state]

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Sid       = "DenyInsecureTransport"
      Effect    = "Deny"
      Principal = "*"
      Action    = "s3:*"
      Resource = [
        "arn:aws:s3:::${local.bucket_name}",
        "arn:aws:s3:::${local.bucket_name}/*",
      ]
      Condition = {
        Bool = { "aws:SecureTransport" = "false" }
      }
    }]
  })
}

resource "aws_s3_bucket_lifecycle_configuration" "state" {
  bucket = aws_s3_bucket.state.id

  # Lifecycle rules need versioning to be configured first.
  depends_on = [aws_s3_bucket_versioning.state]

  rule {
    id     = "expire-old-state-versions"
    status = "Enabled"

    filter {}

    noncurrent_version_expiration {
      noncurrent_days = var.noncurrent_version_expiration_days
    }

    abort_incomplete_multipart_upload {
      days_after_initiation = 7
    }
  }
}
