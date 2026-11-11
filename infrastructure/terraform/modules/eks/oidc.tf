# Register this cluster's service-account token issuer with IAM for IRSA.
# IAM roles will separately restrict which service accounts may assume them.
resource "aws_iam_openid_connect_provider" "cluster" {
  url            = aws_eks_cluster.this.identity[0].oidc[0].issuer
  client_id_list = ["sts.amazonaws.com"]
}
