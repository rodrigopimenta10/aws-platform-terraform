## Live drill: `m3` applied

- Commit: `0793331850bdf81391b82ecdab1e97bb04014d0e`
- Region: `us-east-1`
- Apply took 597s and created 32 resources.
- Hold: 0 minutes. The destroy job starts its hold when it is approved, so destroy begins
  0 minutes after that approval: 01:12 UTC at the earliest.

### Resources by type

| Type | Count |
|---|---|
| `aws_cloudwatch_log_group` | 1 |
| `aws_default_security_group` | 1 |
| `aws_ecr_lifecycle_policy` | 2 |
| `aws_ecr_repository` | 2 |
| `aws_eks_cluster` | 1 |
| `aws_iam_role` | 1 |
| `aws_iam_role_policy_attachment` | 1 |
| `aws_internet_gateway` | 1 |
| `aws_kms_alias` | 2 |
| `aws_kms_key` | 2 |
| `aws_route` | 1 |
| `aws_route_table` | 4 |
| `aws_route_table_association` | 6 |
| `aws_subnet` | 6 |
| `aws_vpc` | 1 |

### Console (what each screenshot should prove)

- [ecr-repositories](https://us-east-1.console.aws.amazon.com/ecr/private-registry/repositories?region=us-east-1): Private repositories platform-live-api and platform-live-worker, both with Immutable tag mutability and KMS encryption
- [ecr-key](https://us-east-1.console.aws.amazon.com/kms/home?region=us-east-1#/kms/keys/6b48b741-e941-4f8b-8515-8965c4fbf91b): The customer-managed key alias platform-live-ecr that encrypts both repositories, enabled, with automatic rotation shown as enabled
- [eks-cluster](https://us-east-1.console.aws.amazon.com/eks/clusters/platform-live-eks?region=us-east-1): Cluster platform-live-eks is Active, runs the pinned Kubernetes version, and shows secrets encryption enabled with the customer-managed key
- [eks-networking](https://us-east-1.console.aws.amazon.com/eks/clusters/platform-live-eks?region=us-east-1): API server endpoint access is Private, in the stack's two private subnets, with the cluster security group
- [eks-key](https://us-east-1.console.aws.amazon.com/kms/home?region=us-east-1#/kms/keys/573cea8d-db22-4dea-9407-b865b90734a0): The customer-managed key alias platform-live-eks, enabled, with automatic rotation shown as enabled
