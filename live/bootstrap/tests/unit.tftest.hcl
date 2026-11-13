# Unit tests: mock provider, plan only. No network, no emulator.
# The state bucket module is replaced by fixed outputs so every policy is fully known at plan time
# (modules/state-backend has its own tests). No Moto test: this stack's point is IAM policy content,
# which Moto stores but does not evaluate.
mock_provider "aws" {
  mock_data "aws_caller_identity" {
    defaults = { account_id = "123456789012" }
  }
  mock_data "aws_partition" {
    defaults = { partition = "aws" }
  }
  mock_data "aws_region" {
    defaults = { region = "us-east-1" }
  }
}

variables {
  alert_email = "alerts@example.com"
}

override_module {
  target = module.state_backend
  outputs = {
    bucket_name = "platform-live-tfstate-123456789012-us-east-1"
    bucket_arn  = "arn:aws:s3:::platform-live-tfstate-123456789012-us-east-1"
    kms_key_arn = "arn:aws:kms:us-east-1:123456789012:key/00000000-0000-0000-0000-000000000000"
  }
}

run "role_name_and_session_length" {
  command = plan

  assert {
    condition     = aws_iam_role.drill.name == "platform-live-drill"
    error_message = "The role must be called platform-live-drill."
  }

  assert {
    condition     = aws_iam_role.drill.max_session_duration == 3600
    error_message = "Sessions must last at most one hour."
  }

  assert {
    condition     = aws_iam_role_policy_attachment.administrator.policy_arn == "arn:aws:iam::aws:policy/AdministratorAccess"
    error_message = "The role should carry AdministratorAccess (bounded by the guardrails policy)."
  }
}

run "oidc_provider_is_github_with_sts_audience" {
  command = plan

  assert {
    condition     = aws_iam_openid_connect_provider.github.url == "https://token.actions.githubusercontent.com"
    error_message = "The OIDC provider must be GitHub Actions'."
  }

  assert {
    condition     = toset(aws_iam_openid_connect_provider.github.client_id_list) == toset(["sts.amazonaws.com"])
    error_message = "The only audience must be sts.amazonaws.com."
  }
}

run "trust_policy_allows_only_the_aws_live_environment" {
  command = plan

  assert {
    condition     = length(jsondecode(aws_iam_role.drill.assume_role_policy).Statement) == 1
    error_message = "The trust policy must have exactly one statement."
  }

  assert {
    condition     = jsondecode(aws_iam_role.drill.assume_role_policy).Statement[0].Principal.Federated == "arn:aws:iam::123456789012:oidc-provider/token.actions.githubusercontent.com"
    error_message = "Only the GitHub OIDC provider may be trusted."
  }

  assert {
    condition     = jsondecode(aws_iam_role.drill.assume_role_policy).Statement[0].Action == "sts:AssumeRoleWithWebIdentity"
    error_message = "The only action must be sts:AssumeRoleWithWebIdentity."
  }

  assert {
    condition     = jsondecode(aws_iam_role.drill.assume_role_policy).Statement[0].Condition.StringEquals["token.actions.githubusercontent.com:sub"] == "repo:rodrigopimenta10@11894505/aws-platform-terraform@1451999319:environment:aws-live"
    error_message = "sub must equal the aws-live environment of this repo, with StringEquals (no wildcards)."
  }

  assert {
    condition     = jsondecode(aws_iam_role.drill.assume_role_policy).Statement[0].Condition.StringEquals["token.actions.githubusercontent.com:aud"] == "sts.amazonaws.com"
    error_message = "aud must equal sts.amazonaws.com."
  }

  assert {
    condition     = keys(jsondecode(aws_iam_role.drill.assume_role_policy).Statement[0].Condition) == ["StringEquals"]
    error_message = "Only exact-match conditions are allowed in the trust policy."
  }
}

run "guardrails_are_all_denies" {
  command = plan

  assert {
    condition     = alltrue([for s in jsondecode(aws_iam_role_policy.guardrails.policy).Statement : s.Effect == "Deny"])
    error_message = "The guardrails policy may only contain Deny statements."
  }
}

run "region_guardrail_exempts_global_services_only" {
  command = plan

  assert {
    condition = one([
      for s in jsondecode(aws_iam_role_policy.guardrails.policy).Statement : s.Condition.StringNotEquals["aws:RequestedRegion"]
      if s.Sid == "DenyOutsideDrillRegion"
    ]) == ["us-east-1"]
    error_message = "Every region but us-east-1 must be denied."
  }

  assert {
    condition = length(setsubtract(
      ["iam:*", "sts:*", "cloudfront:*", "route53:*", "budgets:*"],
      one([for s in jsondecode(aws_iam_role_policy.guardrails.policy).Statement : s.NotAction if s.Sid == "DenyOutsideDrillRegion"]),
    )) == 0
    error_message = "IAM, STS, CloudFront, Route 53 and Budgets must be exempt from the region deny."
  }

  assert {
    condition = length(setintersection(
      ["ec2:*", "s3:*", "kms:*", "eks:*", "lambda:*"],
      one([for s in jsondecode(aws_iam_role_policy.guardrails.policy).Statement : s.NotAction if s.Sid == "DenyOutsideDrillRegion"]),
    )) == 0
    error_message = "Regional services must not be exempt from the region deny."
  }
}

run "denies_long_lived_identities_and_account_changes" {
  command = plan

  assert {
    condition = length(setsubtract(
      ["iam:CreateUser", "iam:CreateAccessKey", "iam:CreateLoginProfile", "iam:UpdateLoginProfile", "organizations:*", "account:*"],
      one([for s in jsondecode(aws_iam_role_policy.guardrails.policy).Statement : s.Action if s.Sid == "DenyLongLivedIdentitiesAndAccountChanges"]),
    )) == 0
    error_message = "User, access key, login profile, Organizations and account actions must be denied."
  }
}

run "role_and_oidc_provider_are_protected" {
  command = plan

  assert {
    condition     = toset(one([for s in jsondecode(aws_iam_role_policy.guardrails.policy).Statement : s.Resource if s.Sid == "DenyChangesToThisRole"])) == toset(["arn:aws:iam::123456789012:role/platform-live-drill", "arn:aws:iam::123456789012:role/platform-live-drill-budgets-action"])
    error_message = "The self-protection statement must target this role and the budgets action role."
  }

  assert {
    condition = length(setsubtract(
      ["iam:AttachRolePolicy", "iam:PutRolePolicy", "iam:DeleteRolePolicy", "iam:UpdateAssumeRolePolicy", "iam:DeleteRole"],
      one([for s in jsondecode(aws_iam_role_policy.guardrails.policy).Statement : s.Action if s.Sid == "DenyChangesToThisRole"]),
    )) == 0
    error_message = "The role must not be able to change its own policies or trust."
  }

  assert {
    condition     = one([for s in jsondecode(aws_iam_role_policy.guardrails.policy).Statement : s.Resource if s.Sid == "DenyChangesToGitHubOidcProvider"]) == "arn:aws:iam::123456789012:oidc-provider/token.actions.githubusercontent.com"
    error_message = "The OIDC provider must be protected."
  }
}

run "bootstrap_state_is_protected" {
  command = plan

  assert {
    condition     = one([for s in jsondecode(aws_iam_role_policy.guardrails.policy).Statement : s.Resource if s.Sid == "DenyWritesToBootstrapState"]) == "arn:aws:s3:::platform-live-tfstate-123456789012-us-east-1/bootstrap/*"
    error_message = "The drill must not write or delete the bootstrap stack's own state."
  }

  assert {
    condition     = contains(one([for s in jsondecode(aws_iam_role_policy.guardrails.policy).Statement : s.Action if s.Sid == "DenyChangesToStateBucket"]), "s3:DeleteBucket")
    error_message = "The drill must not delete the state bucket."
  }
}

run "other_repository_and_environment_flow_into_trust" {
  command = plan

  variables {
    github_repository    = "example-org/infra"
    github_owner_id      = "1001"
    github_repository_id = "2002"
    github_environment   = "sandbox"
  }

  assert {
    condition     = jsondecode(aws_iam_role.drill.assume_role_policy).Statement[0].Condition.StringEquals["token.actions.githubusercontent.com:sub"] == "repo:example-org@1001/infra@2002:environment:sandbox"
    error_message = "Variables should flow into the subject condition."
  }
}

run "rejects_sessions_longer_than_an_hour" {
  command = plan

  variables {
    max_session_duration = 7200
  }

  expect_failures = [var.max_session_duration]
}

run "rejects_wildcard_repository" {
  command = plan

  variables {
    github_repository = "rodrigopimenta10/*"
  }

  expect_failures = [var.github_repository]
}

run "drill_role_carries_the_boundary" {
  command = plan

  assert {
    condition     = aws_iam_policy.boundary.name == "platform-live-drill-boundary"
    error_message = "The boundary policy must be called platform-live-drill-boundary."
  }

  assert {
    condition     = jsondecode(aws_iam_policy.boundary.policy).Statement[0].Effect == "Allow" && alltrue([for s in slice(jsondecode(aws_iam_policy.boundary.policy).Statement, 1, length(jsondecode(aws_iam_policy.boundary.policy).Statement)) : s.Effect == "Deny"])
    error_message = "The boundary is one Allow * followed only by denies."
  }
}

run "new_roles_must_carry_the_boundary" {
  command = plan

  assert {
    condition = one([
      for s in jsondecode(aws_iam_role_policy.guardrails.policy).Statement : s.Condition.StringNotEquals["iam:PermissionsBoundary"]
      if s.Sid == "DenyRolesWithoutTheBoundary"
    ]) == "arn:aws:iam::123456789012:policy/platform-live-drill-boundary"
    error_message = "CreateRole must be denied unless the new role carries the drill boundary."
  }

  assert {
    condition     = contains([for s in jsondecode(aws_iam_policy.boundary.policy).Statement : s.Sid], "DenyRolesWithoutTheBoundary")
    error_message = "Roles created by drill-created roles must be bound too (the rule lives in the boundary as well)."
  }
}

run "only_allowed_services_and_small_instances" {
  command = plan

  assert {
    condition = alltrue([
      for svc in ["sagemaker:*", "rds:*", "aws-marketplace:*", "servicequotas:*", "savingsplans:*", "support:*"] :
      !contains(one([for s in jsondecode(aws_iam_role_policy.guardrails.policy).Statement : s.NotAction if s.Sid == "DenyServicesDrillsDoNotUse"]), svc)
    ])
    error_message = "Expensive or account-level services must stay outside the allowlist."
  }

  assert {
    condition = alltrue([
      for t in one([for s in jsondecode(aws_iam_role_policy.guardrails.policy).Statement : s.Condition.StringNotLike["ec2:InstanceType"] if s.Sid == "DenyLargeInstanceTypes"]) :
      startswith(t, "t3.") || startswith(t, "t4g.")
    ])
    error_message = "Only t3 and t4g instance types are allowed by default."
  }
}

run "guard_budget_stops_the_drill_role" {
  command = plan

  assert {
    condition     = aws_budgets_budget_action.stop_drills.approval_model == "AUTOMATIC" && aws_budgets_budget_action.stop_drills.action_type == "APPLY_IAM_POLICY"
    error_message = "The budget action must apply the stop policy automatically."
  }

  assert {
    condition     = aws_budgets_budget.guard.limit_amount == "15" && aws_budgets_budget.guard.time_unit == "MONTHLY"
    error_message = "Default guard budget is 15 USD a month."
  }

  assert {
    condition     = jsondecode(aws_iam_policy.stop.policy).Statement[0].Action == "*" && jsondecode(aws_iam_policy.stop.policy).Statement[0].Effect == "Deny"
    error_message = "The stop policy denies everything."
  }

  assert {
    condition     = jsondecode(aws_iam_role_policy.budgets_action.policy).Statement[0].Condition.ArnEquals["iam:PolicyARN"] == "arn:aws:iam::123456789012:policy/platform-live-drill-stop"
    error_message = "AWS Budgets may attach only the stop policy."
  }
}

run "rejects_bad_alert_email" {
  command = plan

  variables {
    alert_email = "not-an-email"
  }

  expect_failures = [var.alert_email]
}
