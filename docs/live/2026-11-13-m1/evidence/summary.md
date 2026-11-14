## Live drill: `m1` applied

- Commit: `0af21656c10aa5dadfbd7a35ac246a33b7ecead8`
- Region: `us-east-1`
- Apply took 59s and created 33 resources.
- Hold: 0 minutes. The destroy job starts its hold when it is approved, so destroy begins
  0 minutes after that approval: 00:39 UTC at the earliest.

### Resources by type

| Type | Count |
|---|---|
| `aws_default_security_group` | 1 |
| `aws_internet_gateway` | 1 |
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
- [sts-endpoint-details](https://us-east-1.console.aws.amazon.com/vpcconsole/home?region=us-east-1#EndpointDetails:vpcEndpointId=vpce-0d5e4ad6694029cac): STS interface endpoint with private DNS names enabled, in the drill VPC
- [sts-endpoint-subnets](https://us-east-1.console.aws.amazon.com/vpcconsole/home?region=us-east-1#EndpointDetails:vpcEndpointId=vpce-0d5e4ad6694029cac): The endpoint has a network interface in each of the 2 private subnets
- [sts-endpoint-security-group](https://us-east-1.console.aws.amazon.com/vpcconsole/home?region=us-east-1#SecurityGroup:securityGroupId=sg-0c31568432123edbe): The endpoint's own security group allows only HTTPS (443) from 10.0.0.0/16
- [s3-gateway-endpoint-routes](https://us-east-1.console.aws.amazon.com/vpcconsole/home?region=us-east-1#EndpointDetails:vpcEndpointId=vpce-0cd4ebbcb801eef4c): The S3 gateway endpoint is attached to both private route tables and the isolated one
