# EKS — control plane and baseline workers

Production passes the networking module's private subnet IDs to this module.
EKS infers the VPC from those subnets. No public worker nodes are created.

## What main.tf defines

1. `aws_iam_role.cluster`: a service role trusted by EKS. `jsonencode` turns the
   Terraform policy object into JSON, which IAM expects. This is not your login role.
2. `aws_iam_role_policy_attachment.cluster`: attaches AWS's `AmazonEKSClusterPolicy`
   to that role so EKS can manage its required AWS resources.
3. `aws_eks_cluster.this`: creates the Kubernetes control plane using version 1.35.
   `depends_on` makes Terraform attach the role permissions before creating EKS.

## Endpoint access

- `endpoint_private_access = true`: workers will contact the API inside the VPC.
- `endpoint_public_access = true`: laptops can contact the API over the internet.
- `public_access_cidrs = ["0.0.0.0/0"]`: any IPv4 source can reach the public API,
  as requested. This changes the original ticket's network restriction design.
  IAM authentication and Kubernetes permissions are still required.

## Intentionally unfinished

Authentication uses EKS access entries (`authentication_mode = "API"`). Automatic
cluster-creator admin access is disabled so operator permissions will be explicit.
The operator access entry registers the existing SSO role supplied through
`operator_role_arn`. Its policy association grants `AmazonEKSClusterAdminPolicy`
across this cluster. Mahin and Isaiah use the same AdministratorAccess SSO role,
so both are covered; anyone else assigned that same role is also covered.
This policy grants Kubernetes permissions, not additional AWS IAM permissions.

After apply, each operator signs in with their own SSO session and runs:

```bash
aws eks update-kubeconfig --name order-platform-prod --region eu-west-2 --profile production
kubectl get namespaces
```

Use each person's local profile name if different. `update-kubeconfig` configures
kubectl's connection; it does not grant access. If Identity Center deletes and
recreates this role, its ARN can change and the Terraform input must be updated.

Managed nodes and their IAM role are now defined in `nodes.tf`. Add-on management
and runtime verification remain later steps. This is not a complete running application cluster or completed ticket.
Applying this step creates a chargeable EKS control plane even without nodes.

Validation: formatting checked; no AWS apply or runtime checks performed.

References:
- https://docs.aws.amazon.com/eks/latest/userguide/cluster-endpoint.html
- https://docs.aws.amazon.com/eks/latest/userguide/access-entries.html
- https://docs.aws.amazon.com/eks/latest/userguide/kubernetes-versions.html

## Worker nodes (`nodes.tf`)

- One managed node group uses the three private subnets: desired/minimum three
  workers, maximum four. Auto Scaling attempts AZ balance; this is not a hard
  guarantee of exactly one node in each AZ. No workload-driven autoscaler is installed.
- Each worker is an On-Demand `t3.small` (2 vCPUs, 2 GiB RAM), running the EKS
  Amazon Linux 2023 x86_64 AMI with 20 GiB root storage. This is a starting estimate,
  not verified application capacity. T3 instances are burstable; sustained CPU
  usage and CPU-credit charges must be considered when sizing after measurement.
- Workers use a separate EC2-trusted IAM role with worker, ECR pull and VPC CNI
  permissions. The CNI policy is initially on the node role; AWS recommends moving
  it to a dedicated CNI service-account identity. It does not grant SQS access to apps.
- EKS manages node registration/access for this managed node group. There is no
  human admin policy on the node role and no SSH configuration.
- The EKS-managed cluster security group is used by default. Its defaults are not
  a completed least-privilege security-group design; that review remains open.
- Private subnets have no public IP auto-assignment or direct internet route.
  NAT routes provide outbound connectivity. Successful ECR/S3/API connectivity
  and the nodes' actual private-only addresses must still be verified after apply.

The normal EKS bootstrap add-ons have not been disabled. VPC CNI is now declared as a Terraform-managed EKS add-on. CoreDNS and kube-proxy are also declared as managed add-ons.
Node creation/health and add-on health have not been tested.

## Choosing capacity

Worker AMI, instance types, capacity type, disk, scaling counts and update
concurrency are module inputs with explicit values in the module call in production `main.tf`. Existing IAM policy names remain fixed because they define
this module's worker permissions, rather than environment sizing choices.

Three workers is an initial availability choice for three-AZ coverage, not a
measured requirement. A multi-AZ node group attempts to balance nodes; it does
not guarantee one in each AZ or spread application replicas automatically.

There is no fixed services-per-node count. Kubernetes schedules pods based on
CPU/memory requests against allocatable resources. System pods consume resources
and pod slots too. Networking IP capacity, kubelet pod limits, disk and placement
rules can constrain scheduling before CPU or memory is full. Measure these on the
running cluster before claiming application capacity.

Increasing app replicas and adding nodes are different actions. Workload-driven
node autoscaling is not installed; the node group's maximum alone does not add
nodes when pods are pending. We can change the desired count manually initially,
then introduce a node autoscaler as a separate learning step.

## VPC CNI add-on

Two blocks at the bottom of `main.tf` manage the CNI:

- `data.aws_eks_addon_version.vpc_cni` reads AWS's default compatible version.
  It creates nothing. This is a dynamic lookup, not a permanently pinned version;
  review future plans because AWS can change the default.
- `aws_eks_addon.vpc_cni` manages that version on the cluster. On initial creation,
  `OVERWRITE` allows takeover of fields from the bootstrapped self-managed CNI.
  Updates use the provider's default conflict behaviour (no forced overwrite).

The default self-managed bootstrap add-ons remain enabled, so worker nodes can
start before this managed CNI resource takes over. The managed add-on waits for
the baseline node group. No node-to-add-on dependency is added, avoiding a cycle.
IAM is unchanged: CNI uses `AmazonEKS_CNI_Policy` on the node role.
No custom prefix delegation or network-policy settings are enabled in this step.

## CoreDNS add-on

The CoreDNS blocks in `main.tf` use the same pattern as VPC CNI: look up AWS's
compatible default version, then manage that version as an EKS add-on. The version
lookup is dynamic, so review later plans for version changes. On creation,
`OVERWRITE` permits replacement of conflicting bootstrap settings.

CoreDNS translates service names such as `order-service` into addresses pods can
use. It waits for the managed CNI add-on, which already waits for worker nodes.
No new IAM policies or custom DNS settings are added in this step. DNS resolution
must still be tested after apply; Terraform validation does not prove DNS works.

## kube-proxy add-on

The final two blocks in `main.tf` look up AWS's default compatible kube-proxy
version and declare the EKS-managed add-on. kube-proxy maintains rules on worker
nodes so Kubernetes Service traffic reaches pods. It waits for the worker group;
no new IAM permissions are added. Initial creation permits overwriting conflicting
bootstrap settings, matching the other add-ons. Version lookups are dynamic and
future plans must be reviewed. Service connectivity still needs testing after apply.
