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
