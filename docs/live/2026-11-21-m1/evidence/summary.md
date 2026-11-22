## Live drill: `m1` applied

- Commit: `f5d3a10a39f0bed1e9b25996fca2d67d5bf515c5`
- Region: `us-east-1`
- Apply took 61s and created 39 resources.
- Hold: 0 minutes. The destroy job starts its hold when it is approved, so destroy begins
  0 minutes after that approval: 01:22 UTC at the earliest.

### Resources by type

| Type | Count |
|---|---|
| `aws_cloudwatch_log_group` | 1 |
| `aws_default_security_group` | 1 |
| `aws_flow_log` | 1 |
| `aws_iam_role` | 1 |
| `aws_iam_role_policy` | 1 |
| `aws_internet_gateway` | 1 |
| `aws_kms_alias` | 1 |
| `aws_kms_key` | 1 |
| `aws_route` | 1 |
| `aws_route_table` | 4 |
| `aws_route_table_association` | 6 |
| `aws_security_group` | 4 |
| `aws_subnet` | 6 |
| `aws_vpc` | 1 |
| `aws_vpc_endpoint` | 5 |
| `aws_vpc_security_group_ingress_rule` | 4 |

### Console (what each screenshot should prove)

- [endpoints](https://us-east-1.console.aws.amazon.com/vpcconsole/home?region=us-east-1#Endpoints:search=platform-live): 5 endpoints: the S3 gateway endpoint plus ECR api, ECR dkr, STS and Logs interface endpoints, all named platform-live-<service>-vpce
- [sts-endpoint-details](https://us-east-1.console.aws.amazon.com/vpcconsole/home?region=us-east-1#EndpointDetails:vpcEndpointId=vpce-05ec4416f7f7a9c68): STS interface endpoint with private DNS names enabled, in the drill VPC
- [sts-endpoint-subnets](https://us-east-1.console.aws.amazon.com/vpcconsole/home?region=us-east-1#EndpointDetails:vpcEndpointId=vpce-05ec4416f7f7a9c68): The endpoint has a network interface in each of the 2 private subnets
- [sts-endpoint-security-group](https://us-east-1.console.aws.amazon.com/vpcconsole/home?region=us-east-1#SecurityGroup:securityGroupId=sg-05b7f66aae4495b2d): The endpoint's own security group allows only HTTPS (443) from 10.0.0.0/16
- [s3-gateway-endpoint-routes](https://us-east-1.console.aws.amazon.com/vpcconsole/home?region=us-east-1#EndpointDetails:vpcEndpointId=vpce-00cfd38d48d3afc1a): The S3 gateway endpoint is attached to both private route tables and the isolated one
- [vpc-flow-logs](https://us-east-1.console.aws.amazon.com/vpcconsole/home?region=us-east-1#VpcDetails:VpcId=vpc-0738d728f4c3c5e5d): A flow log on the VPC: filter ALL, destination type CloudWatch Logs, destination the platform-live-flow-logs log group, status Active
- [flow-log-group](https://us-east-1.console.aws.amazon.com/cloudwatch/home?region=us-east-1#logsV2:log-groups$3FlogGroupNameFilter$3Dplatform-live-flow-logs): The log group /aws/vpc/flow-logs/platform-live-flow-logs with 1 year retention and a KMS key ID shown
