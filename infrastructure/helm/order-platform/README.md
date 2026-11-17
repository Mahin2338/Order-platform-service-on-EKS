# Order platform chart

One folder per service under templates. Shared settings are in values.yaml;
production image versions, resources and Secret/role references are in values-prod.yaml.

| Service | Port | Connections | AWS role |
| --- | --- | --- | --- |
| api-gateway | 8080 | Backend HTTP APIs; JWT Secret | None |
| order-service | 8081 | RDS, SQS send | Dedicated send-only role |
| inventory-service | 8082 | RDS | None |
| payment-service | 8083 | RDS, SQS send | Dedicated send-only role |
| notification-service | 8084 | RDS | None |
| shipping-service | 8085 | RDS, SQS send | Dedicated send-only role |
| dashboard-api | 8086 | RDS; serves dashboard assets/API | None |
| scheduler | 8091 (health only) | RDS background jobs | None |
| worker | 8090 (health only) | SQS receive/delete, backend HTTP APIs | Dedicated consumer role |

Worker consumes SQS events and invokes the backend APIs. It has no database
connection or incoming application Service.
Scheduler runs as one continuously running Deployment, matching its Go process;
it is not a Kubernetes CronJob and does not need a Service for incoming app requests.

The database clients currently share the bootstrap-created ordersapp login and
order-service-secrets Secret. That name is retained to avoid rotating or copying
credentials during this change. Each database pod mounts rds-ca for TLS verification.
Per-service database grants and separate migration credentials are future work.

## Before deploying the additional services

- Apply the Terraform payment/shipping/worker IAM role changes after reviewing the plan.
- Confirm the referenced image tags exist in ECR, especially after nightly destroy.
- Run scripts/bootstrap-database.py after recreating RDS/EKS.
- The bootstrap script also creates the gateway JWT Secret in the same namespace.
- Use namespace order-platform-prod, matching the IAM trust rules and Secrets.

Preview without deployment:

```bash
helm lint infrastructure/helm/order-platform \
  -f infrastructure/helm/order-platform/values-prod.yaml
helm template order-platform infrastructure/helm/order-platform \
  -f infrastructure/helm/order-platform/values-prod.yaml \
  --namespace order-platform-prod
```

All configured services render together; these commands do not deploy them.
The application resources were applied using rendered YAML and
kubectl, not installed as a Helm release. Keep that distinction when choosing a
future release/deployment workflow.

Health checks prove process/database reachability, not complete business behaviour.
Dashboard/scheduler query tables owned by the other apps, so test them after those
apps have created their tables. CPU/memory values are initial test settings, not
load-tested production sizing. Public access and Redis rate limiting remain unconfigured.

## Demo external access

Prod enables one internet-facing ALB through templates/ingress.yaml. Only IPv4
clients listed in ingress.allowedCidrs can reach HTTP port 80. Update this list
when your public IP changes or to add another operator's /32 address.

Routing keeps the URL unchanged: /api and /auth go to api-gateway:8080; everything
else (including /dashboard endpoints and website assets) goes to dashboard-api:8086.
The frontend already uses window.location.origin, so no image rebuild is needed.
This is an IP-restricted demo: login accepts arbitrary credentials and dashboard
endpoints are reached directly. HTTP is unencrypted; do not use real credentials.
There is no domain, TLS certificate or claim of production-ready authentication.

Apply the controller IAM and install the controller before upgrading this chart.
The controller discovers tagged public subnets and creates the ALB. Installing or
upgrading the chart with ingress.enabled=true starts ALB charges.

Before nightly Terraform destroy, disable ingress and upgrade this release (or
uninstall the application release) while the controller still runs. Wait until
AWS has deleted the ALB and its related resources, then destroy infrastructure.
Terraform does not directly manage the controller-created ALB.
