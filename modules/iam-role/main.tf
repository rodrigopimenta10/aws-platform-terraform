# The way platform roles get created: an IAM role that refuses to exist without a permissions boundary.
# Terraform cannot stop someone writing a bare `aws_iam_role`, but every role the platform's own modules
# create can go through here. The precondition fails the plan, before anything reaches AWS, when no
# boundary is given. (The boundary policy's own Deny does the same on the AWS side; see modules/iam-boundary.)

module "labels" {
  source = "../labels"

  project     = var.project
  environment = var.environment
  owner       = var.owner
  components  = [var.name]
}

locals {
  name = module.labels.names[var.name]
}

resource "aws_iam_role" "this" {
  name                 = local.name
  description          = var.description
  assume_role_policy   = var.assume_role_policy
  max_session_duration = var.max_session_duration
  permissions_boundary = var.permissions_boundary

  tags = merge(module.labels.tags, { Name = local.name })

  lifecycle {
    precondition {
      condition     = var.permissions_boundary != null
      error_message = "Role ${local.name} has no permissions boundary. Pass the boundary policy ARN (modules/iam-boundary output policy_arn): without one, attaching AdministratorAccess to this role would make it unlimited."
    }
  }
}

resource "aws_iam_role_policy_attachment" "this" {
  for_each = toset(var.managed_policy_arns)

  role       = aws_iam_role.this.name
  policy_arn = each.value
}
