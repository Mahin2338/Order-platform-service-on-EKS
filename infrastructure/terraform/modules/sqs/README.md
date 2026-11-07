# Application SQS queues

Production calls this module to create two encrypted Standard queues:

| Queue | Purpose | Retention |
|---|---|---|
| `order-events` | Order/payment/shipping send events; the worker service receives and deletes | 4 days |
| `order-events-dlq` | Holds messages moved out after repeated receives without successful deletion | 14 days |

`max_receive_count = 5` is the receive threshold used by SQS redrive. SQS counts
receives, not application error logs. A successful handler must delete its message.
The DLQ redrive allow policy permits only the main queue to use it as a DLQ;
it does not grant application send/receive permissions.

Received messages stay hidden for 600 seconds (10 minutes). This is an initial
estimate allowing for a batch of up to 10 messages processed sequentially by the
worker service, with multiple downstream HTTP calls. SDK retries/deletion delays
can add time; measure batch processing time before treating this as sufficient.
A longer timeout also means a crashed worker's messages take longer to retry.
Queue long polling defaults to 20 seconds; the current worker explicitly requests
the same value. Encryption uses SQS-owned keys, so no customer KMS role is needed.

Standard queues can deliver duplicate or out-of-order events. This configuration
does not add idempotency, ordering, visibility extension or reliable publishing
from database transactions. Some application handlers ignore errors; a successful
handler return/deletion is not proof that every downstream action succeeded.
For Standard queues, moving a message to the DLQ preserves its original enqueue
time for expiry. Four days in the main queue leaves less than the full 14 days
remaining in the DLQ. Deleting a queue also deletes its messages.

## File guide

- `main.tf`: main queue, DLQ and DLQ source restriction.
- `variables.tf`: inputs chosen in production `main.tf`.
- `outputs.tf`: URLs for application settings and ARNs for IAM policies.
- `versions.tf`: Terraform/provider compatibility.

After a reviewed apply, `terraform output -raw sqs_queue_url` from the production
folder gives the SQS_QUEUE_URL for the four queue clients. Also set AWS_REGION and
use pod IAM identities. The queue URL is configuration, not a credential.

## Remaining work

No application pod IAM permissions or Kubernetes settings are added by this module.
Producers need SendMessage only on the main ARN; the worker needs ReceiveMessage
and DeleteMessage only there. Normal application roles do not need DLQ access.

Before declaring the wider ticket complete, apply a reviewed plan and test
send/receive/delete and repeated receives leading to the DLQ with a test message.
Use a temporary short-timeout test queue for quick redrive tests rather than
changing the application timeout. Test that unrelated APIs/queues are denied after
workload roles exist. No live delivery/redrive test has been performed here.
