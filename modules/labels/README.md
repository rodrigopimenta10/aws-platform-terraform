# labels

Builds the resource-name prefix and the standard tag map that every other module in this repo uses.
It creates **no AWS resources**, so it costs nothing and has nothing to destroy.

## Inputs

| Name | Type | Default | Description |
|------|------|---------|-------------|
| `project` | `string` | n/a (required) | Short project name, 2-20 chars, lowercase letters/digits/hyphens, starts with a letter. |
| `environment` | `string` | n/a (required) | One of `dev`, `staging`, `prod`, `live` (live-drill stacks). |
| `owner` | `string` | n/a (required) | Team or person responsible. No email addresses. |
| `components` | `set(string)` | `[]` | Component names to build full names for (`vpc`, `flow-logs`, ...). |
| `extra_tags` | `map(string)` | `{}` | Extra tags. Cannot override the standard four. Keys starting `aws:` are rejected. |

## Outputs

| Name | Description |
|------|-------------|
| `prefix` | `<project>-<environment>`, for example `platform-dev`. |
| `names` | Map of component to `<prefix>-<component>`. |
| `tags` | `project`, `environment`, `owner`, `managed-by = "terraform"`, plus `extra_tags`. |

## Example

```hcl
module "labels" {
  source = "../../modules/labels"

  project     = "platform"
  environment = "dev"
  owner       = "platform-team"
  components  = ["vpc", "flow-logs"]
}

provider "aws" {
  region = "us-east-1"

  default_tags {
    tags = module.labels.tags
  }
}

resource "aws_cloudwatch_log_group" "flow" {
  name = "/${module.labels.names["flow-logs"]}" # /platform-dev-flow-logs
}
```

## Why it's built this way

- **One place for names and tags.** If every module invented its own naming, you could not find
  resources in the console, write IAM policies by name prefix, or attribute cost by tag. See
  [ADR 0002](../../docs/adr/0002-naming-and-tagging.md).
- **No resources, pure `locals`.** A module that only computes values is trivially testable with
  `terraform plan` and has no blast radius.
- **Standard tags are merged last** so a caller cannot accidentally set `managed-by = "hand"` or hide the
  real owner through `extra_tags`.
- **Strict validation.** Names are lowercase and hyphenated, and `project` is capped at 20 characters,
  because some AWS names have hard limits (for example 32 characters for load balancers and target groups)
  and the prefix, environment and component all have to fit.
- **`owner` rejects `@`.** Tags show up in billing exports and many consoles; the repo is also public.
- **`default_tags` friendly.** Pass `tags` to the provider's `default_tags` and every taggable resource gets
  them without repeating `tags = ...`.

## Testing

`tests/labels.tftest.hcl` uses `mock_provider "aws"` with `command = plan` to check the prefix, the tag map,
component names, that extra tags cannot override standard ones, and that each invalid input is rejected.
There is no Moto integration test because the module creates no resources for Moto to emulate.
