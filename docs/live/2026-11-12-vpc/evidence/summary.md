## Live drill: `vpc` applied

- Commit: `964806098046b6b98f0fb56d38016f75bd088ad2`
- Region: `us-east-1`
- Apply took 13s and created 20 resources.
- Hold: 15 minutes. The destroy job starts its hold when it is approved, so destroy begins
  15 minutes after that approval: 00:31 UTC at the earliest.

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

- [vpc-details](https://us-east-1.console.aws.amazon.com/vpcconsole/home?region=us-east-1#VpcDetails:VpcId=vpc-0725a992a2b660e76): VPC platform-live-vpc, 10.0.0.0/16, DNS resolution and DNS hostnames enabled
- [resource-map](https://us-east-1.console.aws.amazon.com/vpcconsole/home?region=us-east-1#VpcDetails:VpcId=vpc-0725a992a2b660e76): 2 AZs x 3 tiers = 6 subnets, 4 route tables, 1 internet gateway, no NAT gateway
- [subnets](https://us-east-1.console.aws.amazon.com/vpcconsole/home?region=us-east-1#subnets:): 6 subnets named platform-live-vpc-<tier>-<az> (ADR 0002): private /20s, public and isolated /22s
- [public-route-table](https://us-east-1.console.aws.amazon.com/vpcconsole/home?region=us-east-1#RouteTableDetails:RouteTableId=rtb-0bb758695a6fb60ce): 0.0.0.0/0 goes to the internet gateway; associated with both public subnets
- [isolated-route-table](https://us-east-1.console.aws.amazon.com/vpcconsole/home?region=us-east-1#RouteTableDetails:RouteTableId=rtb-0a05f19cc17b8c710): Only the local route: isolated subnets have no way out of the VPC
- [default-security-group](https://us-east-1.console.aws.amazon.com/vpcconsole/home?region=us-east-1#SecurityGroups:): The default security group has no inbound and no outbound rules
- [tags](https://us-east-1.console.aws.amazon.com/vpcconsole/home?region=us-east-1#VpcDetails:VpcId=vpc-0725a992a2b660e76): Standard tags from ADR 0002 (project, environment=live, owner, managed-by) plus live-stack=vpc
