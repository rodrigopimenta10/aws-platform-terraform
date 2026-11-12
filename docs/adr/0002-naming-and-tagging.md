# ADR 0002: One naming scheme and one tag map, from `modules/labels`

- **Status:** accepted
- **Date:** 2026-11-09
- **Amended:** 2026-11-12, `live` added to the environment list for the live drill.

## Context
A **tag** in AWS is a key/value label attached to a resource. Tags drive cost reports ("what did the
`platform` project cost in prod?"), access rules, and clean-up ("what is left over from that experiment?").
Names matter just as much: many AWS resources cannot be renamed after creation, and some have strict
length limits. Without a shared convention every module invents its own, and fixing that later means
replacing resources.

## Decision
- Every name is `<project>-<environment>-<component>`, lowercase with hyphens, for example
  `platform-dev-flow-logs`. `project` is at most 20 characters so the whole name stays under the 32 that
  load balancers and target groups allow.
- Every taggable resource carries four tags: `project`, `environment`, `owner`, and
  `managed-by = "terraform"`. Tag keys are lowercase and hyphenated.
- `modules/labels` computes the prefix, names and tags. Other modules take `project`, `environment` and
  `owner` (or the labels outputs) rather than building strings themselves.
- Roots set the tags once through the AWS provider's `default_tags`, so they apply automatically.
  Callers can add `extra_tags` but cannot override the four standard ones.
- `environment` is one of `dev`, `staging`, `prod`, `live`. A closed list stops `prod` and `production` from
  becoming two cost buckets. `live` (added 2026-11-12) marks the short-lived stacks the live drill applies
  and destroys (`live/`), so anything tagged `environment = live` that outlives a drill is a leak.
- `owner` is a team or alias, never an email address: tags are widely visible and this repo is public.

## Consequences
- Predictable names make IAM policies by prefix and console searches possible.
- Tag-based cost allocation works, but AWS only reports on a tag after it is activated as a cost allocation
  tag in the billing console. That is a manual step outside Terraform here.
- Names are fixed once resources exist. Changing `project` or `environment` later replaces resources.
- Resources with their own tagging rules (for example autoscaling group propagation) need explicit handling
  in their modules.
