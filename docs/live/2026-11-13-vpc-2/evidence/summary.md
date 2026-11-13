## Live drill: `vpc` applied

- Commit: `1a6e1015dfa438ae6d95a3af5962337ecb36db9e`
- Region: `us-east-1`
- Apply took 11s and created 20 resources.
- Hold: 0 minutes. The destroy job starts its hold when it is approved, so destroy begins
  0 minutes after that approval: 14:17 UTC at the earliest.

### Resources by type

| Type | Count |
|---|---|
| `aws_default_security_group` | 1 |
| `aws_internet_gateway` | 1 |
| `aws_route` | 1 |
| `aws_route_table` | 4 |
| `aws_route_table_association` | 6 |
| `aws_subnet` | 6 |
| `aws_vpc` | 1 |

### Console (what each screenshot should prove)

- [vpc-details](https://us-east-1.console.aws.amazon.com/vpcconsole/home?region=us-east-1#VpcDetails:VpcId=vpc-0ae3a908a191864d7): VPC platform-live-vpc, 10.0.0.0/16, DNS resolution and DNS hostnames enabled
- [resource-map](https://us-east-1.console.aws.amazon.com/vpcconsole/home?region=us-east-1#VpcDetails:VpcId=vpc-0ae3a908a191864d7): 2 AZs x 3 tiers = 6 subnets, the stack's route tables, 1 internet gateway, no NAT gateway
- [subnets](https://us-east-1.console.aws.amazon.com/vpcconsole/home?region=us-east-1#subnets:search=platform-live-vpc): 6 subnets named platform-live-vpc-<tier>-<az> (ADR 0002): private /20s, public and isolated /22s
- [public-route-table](https://us-east-1.console.aws.amazon.com/vpcconsole/home?region=us-east-1#RouteTableDetails:RouteTableId=rtb-0e4b4b50f82b19d7e): 0.0.0.0/0 goes to the internet gateway; associated with both public subnets
- [isolated-route-table](https://us-east-1.console.aws.amazon.com/vpcconsole/home?region=us-east-1#RouteTableDetails:RouteTableId=rtb-03afb9fc1884ea26e): Only the local route: isolated subnets have no way out of the VPC
- [tags](https://us-east-1.console.aws.amazon.com/vpcconsole/home?region=us-east-1#VpcDetails:VpcId=vpc-0ae3a908a191864d7): Standard tags from ADR 0002 (project, environment=live, owner, managed-by) plus live-stack=vpc
