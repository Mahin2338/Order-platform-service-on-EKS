# Trust controls WHO may use the role. SQS permissions are added separately.
resource "aws_iam_role" "payment_service" {
  name = "${var.cluster_name}-payment-service"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Principal = {
        Federated = aws_iam_openid_connect_provider.cluster.arn
      }
      Action = "sts:AssumeRoleWithWebIdentity"
      Condition = {
        StringEquals = {
          "${replace(aws_iam_openid_connect_provider.cluster.url, "https://", "")}:aud" = "sts.amazonaws.com"
          "${replace(aws_iam_openid_connect_provider.cluster.url, "https://", "")}:sub" = "system:serviceaccount:${var.application_namespace}:${var.payment_service_account_name}"
        }
      }
    }]
  })
}

# Permissions control WHAT the payment-service role may do in AWS.
resource "aws_iam_role_policy" "payment_service_sqs" {
  name = "send-order-events"
  role = aws_iam_role.payment_service.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = "sqs:SendMessage"
      Resource = var.order_events_queue_arn
    }]
  })
}
