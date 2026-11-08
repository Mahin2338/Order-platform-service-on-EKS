variable "queue_name" {
  description = "Main queue name; the dead-letter queue adds the -dlq suffix."
  type        = string
}

variable "visibility_timeout_seconds" {
  description = "Time received messages stay hidden; allow for a whole sequential worker batch."
  type        = number
}

variable "max_receive_count" {
  description = "Receive-count threshold for moving undeleted messages to the DLQ."
  type        = number
}

variable "event_retention_seconds" {
  description = "How long main-queue messages are retained, measured from original enqueue time."
  type        = number
}

variable "dlq_retention_seconds" {
  description = "DLQ retention; keep longer than the main queue."
  type        = number
}
