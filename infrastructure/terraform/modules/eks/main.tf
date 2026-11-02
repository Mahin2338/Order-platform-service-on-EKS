# This service role is used by EKS, not by human operators or worker nodes.
resource "aws_iam_role" "cluster" {
  name = "${var.cluster_name}-cluster-role"

  # Trust policy: only the EKS service can assume this role.
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "eks.amazonaws.com" }
      Action    = ["sts:AssumeRole", "sts:TagSession"]
    }]
  })
}

# Permissions policy: let EKS manage the AWS resources needed by the cluster.
resource "aws_iam_role_policy_attachment" "cluster" {
  role       = aws_iam_role.cluster.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSClusterPolicy"
}

resource "aws_eks_cluster" "this" {
  name     = var.cluster_name
  version  = "1.35"
  role_arn = aws_iam_role.cluster.arn

  # Human permissions are managed through the access entry below.
  access_config {
    authentication_mode                         = "API"
    bootstrap_cluster_creator_admin_permissions = false
  }

  vpc_config {
    subnet_ids = var.private_subnet_ids

    # Workers use the private endpoint; laptops can reach the public endpoint.
    # Reaching the endpoint does not grant permission to run commands.
    endpoint_private_access = true
    endpoint_public_access  = true
    public_access_cidrs     = ["0.0.0.0/0"]
  }

  # Attach permissions before EKS starts using its service role.
  depends_on = [aws_iam_role_policy_attachment.cluster]
}

# Register the existing operator SSO role as an identity EKS accepts.
resource "aws_eks_access_entry" "operators" {
  cluster_name  = aws_eks_cluster.this.name
  principal_arn = var.operator_role_arn
  type          = "STANDARD"
}

# Give that role administrator permissions inside this Kubernetes cluster.
resource "aws_eks_access_policy_association" "operators" {
  cluster_name  = aws_eks_cluster.this.name
  principal_arn = aws_eks_access_entry.operators.principal_arn
  policy_arn    = "arn:aws:eks::aws:cluster-access-policy/AmazonEKSClusterAdminPolicy"

  access_scope {
    type = "cluster"
  }
}

# Look up AWS's default VPC CNI version compatible with this Kubernetes version.
data "aws_eks_addon_version" "vpc_cni" {
  addon_name         = "vpc-cni"
  kubernetes_version = aws_eks_cluster.this.version
}

# Manage pod networking as an EKS add-on, using the existing node CNI permissions.
resource "aws_eks_addon" "vpc_cni" {
  cluster_name  = aws_eks_cluster.this.name
  addon_name    = "vpc-cni"
  addon_version = data.aws_eks_addon_version.vpc_cni.version

  # Replace conflicting fields when taking over the bootstrapped CNI.
  resolve_conflicts_on_create = "OVERWRITE"

  depends_on = [aws_eks_node_group.baseline]
}

# Look up AWS's default CoreDNS version compatible with this cluster.
data "aws_eks_addon_version" "coredns" {
  addon_name         = "coredns"
  kubernetes_version = aws_eks_cluster.this.version
}

# CoreDNS lets pods find Kubernetes Services by name, such as order-service.
resource "aws_eks_addon" "coredns" {
  cluster_name  = aws_eks_cluster.this.name
  addon_name    = "coredns"
  addon_version = data.aws_eks_addon_version.coredns.version

  # Allow the managed add-on to replace conflicting bootstrap settings.
  resolve_conflicts_on_create = "OVERWRITE"

  # CoreDNS needs workers and working pod networking before it can be healthy.
  depends_on = [aws_eks_addon.vpc_cni]
}

# Look up AWS's default kube-proxy version compatible with this cluster.
data "aws_eks_addon_version" "kube_proxy" {
  addon_name         = "kube-proxy"
  kubernetes_version = aws_eks_cluster.this.version
}

# kube-proxy maintains the rules that route Service traffic to pods.
resource "aws_eks_addon" "kube_proxy" {
  cluster_name  = aws_eks_cluster.this.name
  addon_name    = "kube-proxy"
  addon_version = data.aws_eks_addon_version.kube_proxy.version

  # Allow the managed add-on to replace conflicting bootstrap settings.
  resolve_conflicts_on_create = "OVERWRITE"

  depends_on = [aws_eks_node_group.baseline]
}
