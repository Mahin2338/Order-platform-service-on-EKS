#!/usr/bin/env bash
# Install/upgrade the official controller chart. Run after Terraform apply.
set -euo pipefail

project_root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
terraform_dir="$project_root/infrastructure/terraform/environments/prod"
values_file="$project_root/infrastructure/helm/load-balancer-controller/values-prod.yaml"
chart_version="3.6.2"
cluster_name="order-platform-prod"
region="eu-west-2"
context="order-platform-prod"
account_id="792289066018"
export AWS_PROFILE="${AWS_PROFILE:-production}"
export AWS_EC2_METADATA_DISABLED=true

for command_name in aws terraform kubectl helm; do
  command -v "$command_name" >/dev/null || { echo "Missing command: $command_name" >&2; exit 1; }
done

actual_account="$(aws sts get-caller-identity --query Account --output text)"
if [[ "$actual_account" != "$account_id" ]]; then
  echo "Expected AWS account $account_id; got $actual_account. Stopping." >&2
  exit 1
fi

# The VPC changes after destroy/rebuild, so read it rather than storing it in YAML.
vpc_id="$(terraform -chdir="$terraform_dir" output -raw vpc_id)"
cluster_vpc="$(aws eks describe-cluster --name "$cluster_name" --region "$region" --query cluster.resourcesVpcConfig.vpcId --output text)"
if [[ "$vpc_id" != vpc-* || "$vpc_id" != "$cluster_vpc" ]]; then
  echo "Terraform VPC does not match the current EKS cluster. Stopping." >&2
  exit 1
fi

# Refresh this named context after a cluster rebuild; Helm explicitly targets it.
aws eks update-kubeconfig --name "$cluster_name" --region "$region" \
  --profile "$AWS_PROFILE" --alias "$context"

# This role and its attached permissions must already exist from Terraform apply.
aws iam get-role --role-name "${cluster_name}-load-balancer-controller" \
  --query Role.Arn --output text >/dev/null

echo "Installing controller $chart_version into $context / kube-system"
helm upgrade --install aws-load-balancer-controller aws-load-balancer-controller \
  --repo https://aws.github.io/eks-charts \
  --version "$chart_version" \
  --kube-context "$context" \
  --namespace kube-system \
  --values "$values_file" \
  --set-string "vpcId=$vpc_id" \
  --wait --timeout 5m

kubectl --context "$context" --namespace kube-system \
  get deployment aws-load-balancer-controller
