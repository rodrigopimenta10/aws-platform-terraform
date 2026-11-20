# ecr

**ECR** (Elastic Container Registry) is AWS's private store for container images, the thing you `docker push`
to and that Kubernetes (EKS) pulls from. This module creates one or more repositories that share the same
safe settings. None of the settings has an off switch:

| Setting | Value | Why |
|---------|-------|-----|
| Tag mutability | `IMMUTABLE` | A tag like `v1.2.3` can't be repointed at different code later, so what was tested is what runs. |
| Scan on push | on | Each pushed image is checked against a database of known vulnerabilities (CVEs). |
| Encryption | `KMS`, your key | Images are encrypted with a customer-managed key ([`modules/kms`](../kms/)), so pulling needs permission on the key too, and key use is logged. |
| Lifecycle policy | expire untagged, keep last N | Without one a registry grows forever and you pay for storage of images nobody can name. |

Names and tags come from the [`labels`](../labels/) module: a repository keyed `api` is called
`<project>-<environment>-api`.

## Inputs

| Name | Type | Default | Description |
|------|------|---------|-------------|
| `project` | `string` | n/a (required) | Passed to `labels`. |
| `environment` | `string` | n/a (required) | `dev`, `staging`, `prod` or `live`. |
| `owner` | `string` | n/a (required) | Owner tag value. |
| `repositories` | `map(object)` | n/a (required) | Key to `{ keep_last_images = 30, force_delete = false }`. At least one; keys are lowercase words. `keep_last_images` is 1 to 1000. |
| `kms_key_arn` | `string` | n/a (required) | ARN (not alias) of the KMS key that encrypts the images. |
| `untagged_expiry_days` | `number` | `7` | Days before untagged images expire, 1 to 365. |

## Outputs

| Name | Description |
|------|-------------|
| `repository_urls` | Key to `<account>.dkr.ecr.<region>.amazonaws.com/<name>`, for `docker push` and image fields. |
| `repository_arns` | Key to repository ARN, for IAM policies. |
| `repository_names` | Key to `<project>-<environment>-<key>`. |

## Example

```hcl
module "kms_ecr" {
  source = "../../modules/kms"

  project     = "platform"
  environment = "dev"
  owner       = "platform-team"
  purpose     = "ecr"
  description = "Encrypts platform container images"
}

module "ecr" {
  source = "../../modules/ecr"

  project     = "platform"
  environment = "dev"
  owner       = "platform-team"
  kms_key_arn = module.kms_ecr.key_arn

  repositories = {
    api    = {}                       # keeps the last 30 images
    worker = { keep_last_images = 10 }
  }
}
```

## Why it's built this way

- **Immutable tags, no exceptions.** Mutable tags (`latest`) are convenient and dangerous: a node that
  restarts next week can pull different code from the same tag. CI should push a unique tag, such as the
  git SHA. ECR can exempt tag patterns from immutability; this module does not, to keep the rule simple.
- **Key required.** ECR's default encryption (AES-256 with an AWS-owned key) is free, but you can't see,
  restrict or audit it. A customer-managed key is a few cents a month and gives a second permission gate.
  The key policy must let whoever pushes and pulls use it (in practice the IAM policy does, through
  the key's delegation to IAM, see the `kms` module).
- **Two lifecycle rules.** Rule 1 expires untagged images (leftovers from builds) after a week. Rule 2
  keeps the newest N images of any kind, so a rollback target always exists. Rules run in priority order.
- **`force_delete` defaults to false.** Destroying a repository that holds images fails unless this is
  true, which protects real registries from a careless `terraform destroy`. Drill stacks set it.
- **Not in this module:** repository policies (cross-account pulls) and replication. Add them when something
  needs them.

## Tests

- `tests/unit.tftest.hcl` (mock provider, plan): immutable, scanned and encrypted for every repository,
  both lifecycle rules including per-repository counts, and the validation blocks reject bad input.
- `tests/integration.tftest.hcl` (Moto, apply): creates a real key with `modules/kms`, then the registry,
  and checks what Moto stored. Moto does not enforce lifecycle rules or run scans, so those are asserted
  only as configuration.
