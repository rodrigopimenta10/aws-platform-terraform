output "lb_controller_policy_arn" {
  description = "ARN of the Load Balancer Controller policy, or null when it was not created. Attach it to the controller's role."
  value       = one(aws_iam_policy.lb_controller[*].arn)
}

output "lb_controller_policy_json" {
  description = "The Load Balancer Controller policy document (JSON), for consumers that want to inline it instead."
  value       = local.lb_controller_policy
}

output "karpenter_policy_arn" {
  description = "ARN of the Karpenter controller policy, or null when it was not created. Attach it to Karpenter's role."
  value       = one(aws_iam_policy.karpenter[*].arn)
}

output "karpenter_policy_json" {
  description = "The Karpenter controller policy document (JSON), for consumers that want to inline it instead."
  value       = local.karpenter_policy
}
