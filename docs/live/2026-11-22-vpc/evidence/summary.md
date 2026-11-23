## Live drill: `vpc` applied

- Commit: `74627329e32734be6a412a15ee46f8681cf775f8`
- Region: `us-east-1`
- Apply took 11s and created 20 resources.
- Hold: 0 minutes. The destroy job starts its hold when it is approved, so destroy begins
  0 minutes after that approval: 01:20 UTC at the earliest.

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

- [vpc-details](https://us-east-1.console.aws.amazon.com/vpcconsole/home?region=us-east-1#VpcDetails:VpcId=vpc-02f27120fbe6d61db): VPC platform-live-vpc, 10.0.0.0/16, DNS resolution and DNS hostnames enabled
- [resource-map](https://us-east-1.console.aws.amazon.com/vpcconsole/home?region=us-east-1#VpcDetails:VpcId=vpc-02f27120fbe6d61db): 2 AZs x 3 tiers = 6 subnets, the stack's route tables, 1 internet gateway, no NAT gateway
- [subnets](https://us-east-1.console.aws.amazon.com/vpcconsole/home?region=us-east-1#subnets:search=platform-live-vpc): 6 subnets named platform-live-vpc-<tier>-<az> (ADR 0002): private /20s, public and isolated /22s
- [public-route-table](https://us-east-1.console.aws.amazon.com/vpcconsole/home?region=us-east-1#RouteTableDetails:RouteTableId=rtb-0bce4db7a181eafa9): 0.0.0.0/0 goes to the internet gateway; associated with both public subnets
- [isolated-route-table](https://us-east-1.console.aws.amazon.com/vpcconsole/home?region=us-east-1#RouteTableDetails:RouteTableId=rtb-08a957f022e07037d): Only the local route: isolated subnets have no way out of the VPC
- [tags](https://us-east-1.console.aws.amazon.com/vpcconsole/home?region=us-east-1#VpcDetails:VpcId=vpc-02f27120fbe6d61db): Standard tags from ADR 0002 (project, environment=live, owner, managed-by) plus live-stack=vpc
