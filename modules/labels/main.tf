# This module creates no AWS resources. It only computes names and tags so that every other module
# builds them the same way (see docs/adr/0002-naming-and-tagging.md).
locals {
  # "<project>-<environment>", for example "platform-dev".
  prefix = "${var.project}-${var.environment}"

  # Standard tags win over extra_tags: they are merged last.
  tags = merge(var.extra_tags, {
    project     = var.project
    environment = var.environment
    owner       = var.owner
    managed-by  = "terraform"
  })

  names = { for c in var.components : c => "${local.prefix}-${c}" }
}
