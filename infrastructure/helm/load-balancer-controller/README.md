# AWS Load Balancer Controller

This folder holds values for the official upstream chart, not a new custom chart.
The official chart creates the controller Deployment, service account and Kubernetes
permissions. It is installed separately from the application into kube-system.

Pinned chart version: 3.6.2, controller image v3.6.2, matching the pinned IAM policy.
Verify the downloaded chart's appVersion before installation. Terraform IAM changes
must be applied first. Supply the current VPC ID explicitly at install time using
`--set vpcId=...` from Terraform's `vpc_id` output; do not rely on node metadata.

No Ingress has been configured yet. Installing the controller alone creates no ALB.
The later Ingress will select public subnets, routes and permitted client IPs.

Upstream chart: https://github.com/aws/eks-charts/tree/master/stable/aws-load-balancer-controller

## Install after a rebuild

First apply the prod Terraform configuration, including the controller IAM policy.
Then, from the repository root:

```bash
aws sso login --profile production
bash scripts/install-load-balancer-controller.sh
```

The script checks the AWS account and verifies Terraform's VPC matches the live
cluster, refreshes kubeconfig, checks that the role exists, and runs Helm using
chart version 3.6.2 and this folder's values-prod.yaml. It waits for readiness.
It can be run from any directory and uses AWS_PROFILE=production unless overridden.
Requirements: AWS CLI, Terraform, Helm and kubectl; access to Terraform's state.

First run installs the controller; later runs upgrade/reconcile the same Helm
release. No separate kubectl apply is needed for the controller. Version changes
require reviewing upstream upgrade/CRD instructions and the matching IAM policy;
this script does not manage a cross-version CRD migration.

The application chart is a separate Helm release. Ingress routing still needs to
be added to make the app accessible. This script creates no Ingress or ALB itself.
