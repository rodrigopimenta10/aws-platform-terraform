# ECR (Elastic Container Registry) repositories: where container images are stored. Every repository made
# here gets the same safe defaults, and none of them can be loosened by a variable:
#   - tags are immutable, so "v1.2.3" can never be silently repointed at a different image,
#   - every pushed image is scanned for known vulnerabilities,
#   - images are encrypted at rest with a customer-managed KMS key,
#   - a lifecycle policy expires untagged images quickly and keeps only the newest N tagged ones.

module "labels" {
  source = "../labels"

  project     = var.project
  environment = var.environment
  owner       = var.owner
  components  = keys(var.repositories)
}

resource "aws_ecr_repository" "this" {
  for_each = var.repositories

  name         = module.labels.names[each.key]
  force_delete = each.value.force_delete

  # IMMUTABLE_WITH_EXCLUSIONS is not used: one rule, no exceptions, including "latest".
  image_tag_mutability = "IMMUTABLE"

  image_scanning_configuration {
    scan_on_push = true
  }

  encryption_configuration {
    encryption_type = "KMS"
    kms_key         = var.kms_key_arn
  }

  tags = merge(module.labels.tags, { Name = module.labels.names[each.key] })
}

resource "aws_ecr_lifecycle_policy" "this" {
  for_each = var.repositories

  repository = aws_ecr_repository.this[each.key].name

  # Rules are evaluated in priority order. Untagged images are build leftovers (a tag moved to a newer
  # image, or a multi-arch manifest's parts), so they expire first; the second rule caps what stays.
  policy = jsonencode({
    rules = [
      {
        rulePriority = 1
        description  = "Expire untagged images after ${var.untagged_expiry_days} days"
        selection = {
          tagStatus   = "untagged"
          countType   = "sinceImagePushed"
          countUnit   = "days"
          countNumber = var.untagged_expiry_days
        }
        action = { type = "expire" }
      },
      {
        rulePriority = 2
        description  = "Keep only the last ${each.value.keep_last_images} images"
        selection = {
          tagStatus   = "any"
          countType   = "imageCountMoreThan"
          countNumber = each.value.keep_last_images
        }
        action = { type = "expire" }
      },
    ]
  })
}
