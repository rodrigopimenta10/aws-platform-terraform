# Read by live/evidence.sh and to fill the console URLs in live/screenshots.yml.

output "region" {
  description = "Region the stack was applied in."
  value       = var.region
}

output "tags" {
  description = "Tags every resource gets through the provider's default_tags, including live-stack."
  value       = module.labels.tags
}

output "kms_key_id" {
  description = "ID of the drill KMS key that encrypts the repositories."
  value       = module.kms_ecr.key_id
}

output "ecr_api_repository_name" {
  description = "Name of the api repository."
  value       = module.ecr.repository_names["api"]
}

output "ecr_worker_repository_name" {
  description = "Name of the worker repository."
  value       = module.ecr.repository_names["worker"]
}

output "eks_cluster_name" {
  description = "Name of the EKS cluster."
  value       = module.eks.cluster_name
}

output "eks_kms_key_id" {
  description = "ID of the drill KMS key that encrypts the cluster's Secrets and logs."
  value       = module.kms_eks.key_id
}

output "vpc_id" {
  description = "ID of the VPC the cluster runs in."
  value       = module.vpc.vpc_id
}

output "eks_node_group_names" {
  description = "Map of node group key to node group name, for the console links."
  value       = module.nodes.node_group_names
}

output "eks_system_node_group_name" {
  description = "Name of the on-demand node group that runs a node during the drill."
  value       = module.nodes.node_group_names["system"]
}

output "eks_addon_versions" {
  description = "Map of add-on name to the version installed."
  value       = module.addons.addon_versions
}

output "eks_workload_role_name" {
  description = "Name of the example workload's Pod Identity role."
  value       = module.workload_identity.role_name
}
