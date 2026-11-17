# Unit tests: mock provider, plan only. No network, no emulator.
mock_provider "aws" {
  mock_data "aws_caller_identity" {
    defaults = {
      account_id = "123456789012"
    }
  }

  mock_data "aws_partition" {
    defaults = {
      partition = "aws"
    }
  }
}

variables {
  project           = "platform"
  environment       = "dev"
  owner             = "platform-team"
  github_repository = "example-org/example-repo"
}

run "defaults_trust_only_the_main_branch_of_one_repo" {
  command = plan

  assert {
    condition     = length(aws_iam_openid_connect_provider.github) == 1 && aws_iam_openid_connect_provider.github[0].url == "https://token.actions.githubusercontent.com"
    error_message = "By default the module creates the GitHub provider."
  }

  assert {
    condition     = contains(aws_iam_openid_connect_provider.github[0].client_id_list, "sts.amazonaws.com") && length(aws_iam_openid_connect_provider.github[0].client_id_list) == 1
    error_message = "The provider's audience should be sts.amazonaws.com."
  }

  assert {
    condition     = aws_iam_role.deploy.name == "platform-dev-github-deploy" && aws_iam_role.deploy.max_session_duration == 3600
    error_message = "Role name comes from labels and sessions last an hour."
  }

  assert {
    condition = (
      jsondecode(aws_iam_role.deploy.assume_role_policy).Statement[0].Action == "sts:AssumeRoleWithWebIdentity" &&
      jsondecode(aws_iam_role.deploy.assume_role_policy).Statement[0].Principal.Federated == "arn:aws:iam::123456789012:oidc-provider/token.actions.githubusercontent.com" &&
      jsondecode(aws_iam_role.deploy.assume_role_policy).Statement[0].Condition.StringEquals["token.actions.githubusercontent.com:aud"] == "sts.amazonaws.com"
    )
    error_message = "Trust policy should use web identity federation with the GitHub provider and the STS audience."
  }

  assert {
    condition     = jsondecode(aws_iam_role.deploy.assume_role_policy).Statement[0].Condition.StringEquals["token.actions.githubusercontent.com:sub"] == ["repo:example-org/example-repo:ref:refs/heads/main"]
    error_message = "Only the main branch of the named repository may assume the role."
  }

  assert {
    condition     = strcontains(aws_iam_role.deploy.assume_role_policy, "StringLike") == false
    error_message = "Subjects are matched exactly (StringEquals), never with wildcards."
  }
}

run "branches_environments_and_pull_requests_each_add_an_exact_subject" {
  command = plan

  variables {
    allowed_branches     = ["main", "release"]
    allowed_environments = ["production"]
    allow_pull_requests  = true
  }

  assert {
    condition = output.allowed_subjects == [
      "repo:example-org/example-repo:ref:refs/heads/main",
      "repo:example-org/example-repo:ref:refs/heads/release",
      "repo:example-org/example-repo:environment:production",
      "repo:example-org/example-repo:pull_request",
    ]
    error_message = "Each allowed context should become one exact subject."
  }
}

run "ids_pin_the_subject_to_one_exact_repository" {
  command = plan

  variables {
    github_owner_id      = "1111"
    github_repository_id = "2222"
  }

  assert {
    condition     = output.allowed_subjects == ["repo:example-org@1111/example-repo@2222:ref:refs/heads/main"]
    error_message = "With IDs the subject should be repo:<owner>@<id>/<repo>@<id>:..."
  }
}

run "an_existing_provider_is_trusted_without_creating_another" {
  command = plan

  variables {
    create_provider = false
  }

  assert {
    condition     = length(aws_iam_openid_connect_provider.github) == 0
    error_message = "create_provider = false must not create a provider."
  }

  assert {
    condition     = output.provider_arn == "arn:aws:iam::123456789012:oidc-provider/token.actions.githubusercontent.com"
    error_message = "The role should still trust the account's existing provider."
  }
}

run "boundary_policies_and_session_length_are_passed_through" {
  command = plan

  variables {
    permissions_boundary = "arn:aws:iam::123456789012:policy/platform-boundary"
    managed_policy_arns  = ["arn:aws:iam::aws:policy/ReadOnlyAccess"]
    max_session_duration = 7200
  }

  assert {
    condition     = aws_iam_role.deploy.permissions_boundary == "arn:aws:iam::123456789012:policy/platform-boundary" && aws_iam_role.deploy.max_session_duration == 7200
    error_message = "Boundary and session duration should reach the role."
  }

  assert {
    condition     = length(aws_iam_role_policy_attachment.deploy) == 1
    error_message = "One policy attachment per managed policy ARN."
  }
}

run "no_allowed_context_is_refused" {
  command = plan

  variables {
    allowed_branches = []
  }

  expect_failures = [aws_iam_role.deploy]
}

run "wildcard_branch_is_rejected" {
  command = plan

  variables {
    allowed_branches = ["*"]
  }

  expect_failures = [var.allowed_branches]
}

run "wildcard_repository_is_rejected" {
  command = plan

  variables {
    github_repository = "example-org/*"
  }

  expect_failures = [var.github_repository]
}

run "only_one_id_is_rejected" {
  command = plan

  variables {
    github_owner_id = "1111"
  }

  expect_failures = [var.github_repository_id]
}

run "non_numeric_id_is_rejected" {
  command = plan

  variables {
    github_owner_id      = "abc"
    github_repository_id = "2222"
  }

  expect_failures = [var.github_owner_id]
}

run "session_outside_range_is_rejected" {
  command = plan

  variables {
    max_session_duration = 60
  }

  expect_failures = [var.max_session_duration]
}

run "non_policy_arn_is_rejected" {
  command = plan

  variables {
    managed_policy_arns = ["not-an-arn"]
  }

  expect_failures = [var.managed_policy_arns]
}

run "bad_environment_name_is_rejected" {
  command = plan

  variables {
    allowed_environments = ["prod*"]
  }

  expect_failures = [var.allowed_environments]
}
