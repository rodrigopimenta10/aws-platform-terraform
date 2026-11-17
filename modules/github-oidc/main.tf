# Lets GitHub Actions workflows get short-lived AWS credentials with no stored access keys.
#   1. An OIDC identity provider tells AWS to trust tokens that GitHub signs (optional: an account can
#      have only one per URL).
#   2. A role whose trust policy accepts a token only when its audience is AWS STS and its subject names
#      this repository and one of the allowed branches or environments.
# The role's permissions come from the managed policies the caller attaches. The module grants none itself.

module "labels" {
  source = "../labels"

  project     = var.project
  environment = var.environment
  owner       = var.owner
  components  = ["github-deploy"]
}

data "aws_caller_identity" "current" {}
data "aws_partition" "current" {}

locals {
  name       = module.labels.names["github-deploy"]
  account_id = data.aws_caller_identity.current.account_id
  partition  = data.aws_partition.current.partition

  host = "token.actions.githubusercontent.com"

  # Built from the documented format rather than read from the resource, so the trust policy is known at
  # plan time whether this module creates the provider or the account already has one.
  provider_arn = "arn:${local.partition}:iam::${local.account_id}:oidc-provider/${local.host}"

  # With IDs, GitHub's subject is repo:<owner>@<owner id>/<repo>@<repo id>:<context>.
  repo_part = var.github_owner_id == null ? var.github_repository : "${split("/", var.github_repository)[0]}@${var.github_owner_id}/${split("/", var.github_repository)[1]}@${var.github_repository_id}"

  # One exact subject per allowed context. GitHub builds them as:
  #   ref:refs/heads/<branch>, environment:<name>, pull_request
  subjects = concat(
    [for b in var.allowed_branches : "repo:${local.repo_part}:ref:refs/heads/${b}"],
    [for e in var.allowed_environments : "repo:${local.repo_part}:environment:${e}"],
    var.allow_pull_requests ? ["repo:${local.repo_part}:pull_request"] : [],
  )
}

resource "aws_iam_openid_connect_provider" "github" {
  count = var.create_provider ? 1 : 0

  url = "https://${local.host}"

  # The audience a token must carry. AWS validates GitHub's signature against its own trusted CA list,
  # so no thumbprint is set.
  client_id_list = ["sts.amazonaws.com"]

  tags = module.labels.tags
}

resource "aws_iam_role" "deploy" {
  name                 = local.name
  description          = "Assumed by GitHub Actions runs of ${var.github_repository} through OIDC"
  max_session_duration = var.max_session_duration
  permissions_boundary = var.permissions_boundary

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Sid       = "GitHubActionsOidc"
      Effect    = "Allow"
      Principal = { Federated = local.provider_arn }
      Action    = "sts:AssumeRoleWithWebIdentity"
      Condition = {
        StringEquals = {
          "${local.host}:aud" = "sts.amazonaws.com"
          "${local.host}:sub" = local.subjects
        }
      }
    }]
  })

  tags = merge(module.labels.tags, { Name = local.name })

  lifecycle {
    precondition {
      condition     = length(local.subjects) > 0
      error_message = "Allow at least one branch, environment or pull requests, or no workflow could ever assume the role."
    }
  }

  depends_on = [aws_iam_openid_connect_provider.github]
}

resource "aws_iam_role_policy_attachment" "deploy" {
  for_each = toset(var.managed_policy_arns)

  role       = aws_iam_role.deploy.name
  policy_arn = each.value
}
