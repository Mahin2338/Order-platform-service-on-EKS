output "cluster_name" {
  description = "Cluster name for AWS CLI configuration."
  value       = aws_eks_cluster.this.name
}

output "cluster_endpoint" {
  description = "Kubernetes API address; authentication is still required."
  value       = aws_eks_cluster.this.endpoint
}

output "node_group_name" {
  description = "Name of the baseline managed worker group."
  value       = aws_eks_node_group.baseline.node_group_name
}

output "worker_security_group_id" {
  description = "EKS-created cluster security group also attached to managed workers."
  value       = aws_eks_cluster.this.vpc_config[0].cluster_security_group_id
}

output "order_service_role_arn" {
  description = "IRSA role ARN for the order-service Helm service account."
  value       = aws_iam_role.order_service.arn
}

output "payment_service_role_arn" {
  description = "IRSA role ARN for payment-service."
  value       = aws_iam_role.payment_service.arn
}

output "shipping_service_role_arn" {
  description = "IRSA role ARN for shipping-service."
  value       = aws_iam_role.shipping_service.arn
}

output "worker_role_arn" {
  description = "IRSA role ARN for the application worker, not the EC2 nodes."
  value       = aws_iam_role.worker.arn
}
