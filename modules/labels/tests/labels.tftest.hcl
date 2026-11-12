# Unit tests: the module has no resources, so these only exercise variables and locals.
mock_provider "aws" {}

variables {
  project     = "platform"
  environment = "dev"
  owner       = "platform-team"
}

run "builds_prefix_and_standard_tags" {
  command = plan

  assert {
    condition     = output.prefix == "platform-dev"
    error_message = "prefix should be <project>-<environment>."
  }

  assert {
    condition = output.tags == {
      project     = "platform"
      environment = "dev"
      owner       = "platform-team"
      managed-by  = "terraform"
    }
    error_message = "Standard tags are wrong."
  }

  assert {
    condition     = length(output.names) == 0
    error_message = "names should be empty when no components are given."
  }
}

run "builds_component_names" {
  command = plan

  variables {
    components = ["vpc", "flow-logs"]
  }

  assert {
    condition     = output.names == { vpc = "platform-dev-vpc", "flow-logs" = "platform-dev-flow-logs" }
    error_message = "Component names should be <prefix>-<component>."
  }
}

run "extra_tags_merge_but_never_override" {
  command = plan

  variables {
    extra_tags = {
      cost-center = "learning"
      managed-by  = "hand"
      owner       = "someone-else"
    }
  }

  assert {
    condition     = output.tags["cost-center"] == "learning"
    error_message = "extra_tags should be merged in."
  }

  assert {
    condition     = output.tags["managed-by"] == "terraform" && output.tags["owner"] == "platform-team"
    error_message = "extra_tags must not override standard tags."
  }
}

run "accepts_live_environment" {
  command = plan

  variables {
    environment = "live"
  }

  assert {
    condition     = output.prefix == "platform-live" && output.tags["environment"] == "live"
    error_message = "live is a valid environment for live-drill stacks."
  }
}

run "rejects_unknown_environment" {
  command = plan

  variables {
    environment = "qa"
  }

  expect_failures = [var.environment]
}

run "rejects_uppercase_project" {
  command = plan

  variables {
    project = "Platform"
  }

  expect_failures = [var.project]
}

run "rejects_trailing_hyphen_project" {
  command = plan

  variables {
    project = "platform-"
  }

  expect_failures = [var.project]
}

run "rejects_email_owner" {
  command = plan

  variables {
    owner = "someone@example.com"
  }

  expect_failures = [var.owner]
}

run "rejects_bad_component" {
  command = plan

  variables {
    components = ["VPC"]
  }

  expect_failures = [var.components]
}

run "rejects_reserved_tag_prefix" {
  command = plan

  variables {
    extra_tags = { "aws:cloudformation:stack-name" = "x" }
  }

  expect_failures = [var.extra_tags]
}
