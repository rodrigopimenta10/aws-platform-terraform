## Live drill: `m3` applied

- Commit: `f5d3a10a39f0bed1e9b25996fca2d67d5bf515c5`
- Region: `us-east-1`
- Apply took 719s and created 44 resources.
- Hold: 0 minutes. The destroy job starts its hold when it is approved, so destroy begins
  0 minutes after that approval: 01:44 UTC at the earliest.

### Resources by type

| Type | Count |
|---|---|
| `aws_cloudwatch_log_group` | 1 |
| `aws_default_security_group` | 1 |
| `aws_ecr_lifecycle_policy` | 2 |
| `aws_ecr_repository` | 2 |
| `aws_eip` | 1 |
| `aws_eks_cluster` | 1 |
| `aws_eks_node_group` | 2 |
| `aws_iam_role` | 2 |
| `aws_iam_role_policy_attachment` | 4 |
| `aws_internet_gateway` | 1 |
| `aws_kms_alias` | 2 |
| `aws_kms_key` | 2 |
| `aws_launch_template` | 2 |
| `aws_nat_gateway` | 1 |
| `aws_route` | 3 |
| `aws_route_table` | 4 |
| `aws_route_table_association` | 6 |
| `aws_subnet` | 6 |
| `aws_vpc` | 1 |

### Console (what each screenshot should prove)

- [ecr-repositories](https://us-east-1.console.aws.amazon.com/ecr/private-registry/repositories?region=us-east-1): Private repositories platform-live-api and platform-live-worker, both with Immutable tag mutability and KMS encryption
- [ecr-key](https://us-east-1.console.aws.amazon.com/kms/home?region=us-east-1#/kms/keys/18bb1ace-c92e-4a91-b5e6-2a05ae049f24): The customer-managed key alias platform-live-ecr that encrypts both repositories, enabled, with automatic rotation shown as enabled
- [eks-cluster](https://us-east-1.console.aws.amazon.com/eks/clusters/platform-live-eks?region=us-east-1): Cluster platform-live-eks is Active, runs the pinned Kubernetes version, and shows secrets encryption enabled with the customer-managed key
- [eks-networking](https://us-east-1.console.aws.amazon.com/eks/clusters/platform-live-eks?region=us-east-1): API server endpoint access is Private, in the stack's two private subnets, with the cluster security group
- [eks-key](https://us-east-1.console.aws.amazon.com/kms/home?region=us-east-1#/kms/keys/7f2cb4b5-1adc-4813-851f-adec6a10827f): The customer-managed key alias platform-live-eks, enabled, with automatic rotation shown as enabled
- [eks-compute](https://us-east-1.console.aws.amazon.com/eks/clusters/platform-live-eks?region=us-east-1): Node groups platform-live-nodes-system (On-Demand) and platform-live-nodes-batch (Spot), the first Active with one node
- [eks-node-group](https://us-east-1.console.aws.amazon.com/eks/clusters/platform-live-eks/nodegroups/platform-live-nodes-system?region=us-east-1): Node group platform-live-nodes-system is Active on t3.small with scaling 1 to 2, the workload=system label and the node-group launch template
