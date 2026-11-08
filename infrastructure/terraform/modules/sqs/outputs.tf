output "queue_url" {
  description = "Use as SQS_QUEUE_URL for order, payment, shipping and worker."
  value       = aws_sqs_queue.events.url
}

output "queue_arn" {
  description = "Main queue ARN for narrowly scoped application IAM policies."
  value       = aws_sqs_queue.events.arn
}

output "dlq_url" {
  description = "Dead-letter queue URL for operator inspection."
  value       = aws_sqs_queue.dlq.url
}

output "dlq_arn" {
  description = "Dead-letter queue ARN for monitoring and operator access policies."
  value       = aws_sqs_queue.dlq.arn
}
