# ADR 0004: NAT gateway per AZ by default, one shared gateway as an opt-in

- **Status:** accepted
- **Date:** 2026-11-13

## Context
Resources in private subnets (EKS nodes, for example) have no public IP, so they cannot reach the
internet to pull container images or call AWS APIs. A **NAT gateway** (Network Address Translation) fixes
that: it sits in a public subnet, has an Elastic IP (a fixed public address), and forwards outbound
connections from private subnets while refusing connections started from outside.

A NAT gateway lives in **one availability zone (AZ)**. It bills about $0.045 per hour (about $33 a month)
plus $0.045 per GB it processes, in us-east-1. Prices change, so treat these numbers as rough. The
Elastic IP adds roughly $3.65 a month. Traffic from an AZ to a NAT gateway in a different AZ also pays a
cross-AZ data charge (about $0.01/GB each way).

## Options
| Option | Gateways | Rough monthly fixed cost (3 AZs) | Failure behaviour |
|--------|----------|----------------------------------|-------------------|
| One NAT per AZ | 3 | about $110 | An AZ outage only removes that AZ's egress |
| One shared NAT | 1 | about $37 | If the NAT's AZ fails, every AZ loses egress |
| No NAT | 0 | $0 | Private subnets cannot reach the internet |

## Decision
`modules/vpc` takes two booleans: `enable_nat_gateway` (default `true`) and `single_nat_gateway`
(default `false`). The default is one NAT gateway per AZ, and each AZ's private route table points at the
gateway in its own AZ. Dev environments should set `single_nat_gateway = true`, and drill or
sandbox stacks that need no egress set `enable_nat_gateway = false`.

## Consequences
- The safe choice is the default, and saving money is a visible, deliberate edit.
- Single-NAT mode adds cross-AZ traffic charges and a shared point of failure, which is acceptable
  for dev but not for production.
- Switching modes changes routes and gateways only, because private route tables are already one per AZ.
- NAT gateways are the first part of the platform that costs real money while idle, so the live-drill
  vpc stack sets `enable_nat_gateway = false`.
- Cheaper alternatives, such as VPC endpoints for AWS services (M1.3) or a NAT instance, can cut data
  charges but are not replacements for general internet egress.
