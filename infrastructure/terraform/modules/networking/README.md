# Networking module

Production calls this local module, which calls the community-maintained
[terraform-aws-modules/vpc/aws](https://registry.terraform.io/modules/terraform-aws-modules/vpc/aws/6.6.1)
Registry module pinned to 6.6.1. Terraform downloads its code during `terraform init`;
it still creates resources in your AWS account using your configured provider.

## What it builds

One IPv4 VPC across three AZs. For the default `10.0.0.0/16`:

| AZ position | Private subnet (future workers) | Public subnet (future load balancers/NAT) |
|---|---|---|
| First | 10.0.0.0/20 | 10.0.240.0/24 |
| Second | 10.0.16.0/20 | 10.0.241.0/24 |
| Third | 10.0.32.0/20 | 10.0.242.0/24 |

Subnet ranges are written explicitly in `main.tf`. If you change the VPC CIDR,
update these ranges to fit inside it without overlapping. Keep AZ order stable:
changing it after deployment can replace subnets.

Public subnet route tables send `0.0.0.0/0` to the internet gateway. Private
subnets have no direct internet-gateway route. DNS is enabled so future nodes
can resolve service endpoints. Public IP auto-assignment is disabled.

The public subnet role tag helps a future load-balancer controller find subnets
for the internet-facing app entry point. Private subnets have no internal
load-balancer role tag because the current app does not need an internal load
balancer. Tags do not create a load balancer or grant incoming access.
The default security group has no ingress/egress rules. Future EKS and ingress
resources need their own security groups; subnet ACLs retain the module defaults.

## Outbound access: one NAT gateway per AZ

The module creates three NAT gateways, one in each public subnet. Each private
subnet routes outbound traffic through the NAT gateway in its own AZ:

```text
Private subnet A -> NAT A -> Internet gateway -> Public endpoints
Private subnet B -> NAT B -> Internet gateway -> Public endpoints
Private subnet C -> NAT C -> Internet gateway -> Public endpoints
```

The three Registry module settings are explicit:

- `enable_nat_gateway = true`: create NAT gateways.
- `single_nat_gateway = false`: do not share one NAT across the VPC.
- `one_nat_gateway_per_az = true`: create one NAT in each AZ.

Workers do not need public IPs. NAT allows outbound connections and their
responses, not unsolicited inbound internet connections. Workload security groups
and IAM permissions still need configuring with EKS.

This avoids depending on a shared NAT in another AZ, but incurs three NAT hourly
charges plus data processing and public IPv4 charges. VPC endpoints are not yet
created. A priced NAT/endpoint comparison and live AWS API connectivity checks
remain part of the wider ticket; this network change does not complete them.

## File guide

- `main.tf`: Registry module call and network settings.
- `variables.tf`: inputs and validation.
- `outputs.tf`: IDs passed to future EKS and endpoint resources.
- `versions.tf`: Terraform and AWS provider requirements.

No EKS cluster, nodes, application ingress, or application resources are created.
