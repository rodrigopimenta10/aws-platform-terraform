## Live drill: `m3` applied

- Commit: `beb9ddd7c1f6dc8b5534475cbd9d684e21e9a34a`
- Region: `us-east-1`
- Apply took 832s and created 63 resources.
- Hold: 0 minutes. The destroy job starts its hold when it is approved, so destroy begins
  0 minutes after that approval: 01:36 UTC at the earliest.

### Resources by type

| Type | Count |
|---|---|
| `aws_cloudwatch_log_group` | 1 |
| `aws_default_security_group` | 1 |
| `aws_ecr_lifecycle_policy` | 2 |
| `aws_ecr_repository` | 2 |
| `aws_eip` | 1 |
| `aws_eks_addon` | 5 |
| `aws_eks_cluster` | 1 |
| `aws_eks_node_group` | 2 |
| `aws_eks_pod_identity_association` | 3 |
| `aws_iam_policy` | 2 |
| `aws_iam_role` | 6 |
| `aws_iam_role_policy` | 3 |
| `aws_iam_role_policy_attachment` | 5 |
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
| `terraform_data` | 1 |

### Console (what each screenshot should prove)

- [ecr-repositories](https://us-east-1.console.aws.amazon.com/ecr/private-registry/repositories?region=us-east-1): Private repositories platform-live-api and platform-live-worker, both with Immutable tag mutability and KMS encryption
- [ecr-key](https://us-east-1.console.aws.amazon.com/kms/home?region=us-east-1#/kms/keys/f049addb-177f-4099-9a45-3fd6824d97e0): The customer-managed key alias platform-live-ecr that encrypts both repositories, enabled, with automatic rotation shown as enabled
- [eks-cluster](https://us-east-1.console.aws.amazon.com/eks/clusters/platform-live-eks?region=us-east-1): Cluster platform-live-eks is Active, runs the pinned Kubernetes version, and shows secrets encryption enabled with the customer-managed key
- [eks-networking](https://us-east-1.console.aws.amazon.com/eks/clusters/platform-live-eks?region=us-east-1): API server endpoint access is Private, in the stack's two private subnets, with the cluster security group
- [eks-key](https://us-east-1.console.aws.amazon.com/kms/home?region=us-east-1#/kms/keys/57f1839c-3f9a-4aeb-94a5-18f30c482ebc): The customer-managed key alias platform-live-eks, enabled, with automatic rotation shown as enabled
- [eks-compute](https://us-east-1.console.aws.amazon.com/eks/clusters/platform-live-eks?region=us-east-1): Node groups platform-live-nodes-system (On-Demand) and platform-live-nodes-batch (Spot), the first Active with one node
- [eks-node-group](https://us-east-1.console.aws.amazon.com/eks/clusters/platform-live-eks/nodegroups/platform-live-nodes-system?region=us-east-1): Node group platform-live-nodes-system is Active on t3.small with scaling 1 to 2, the workload=system label and the node-group launch template
- [eks-addons](https://us-east-1.console.aws.amazon.com/eks/clusters/platform-live-eks?region=us-east-1): Add-ons vpc-cni, coredns, kube-proxy, eks-pod-identity-agent and aws-ebs-csi-driver are installed, Active and on the versions the stack pinned
- [eks-pod-identity](https://us-east-1.console.aws.amazon.com/eks/clusters/platform-live-eks?region=us-east-1): A Pod Identity association links service account orders-api in namespace orders to the role platform-live-orders
- [eks-controller-policies](https://us-east-1.console.aws.amazon.com/iam/home?region=us-east-1#/policies): Customer-managed policies platform-live-lb-controller and platform-live-karpenter exist next to the boundary policy
