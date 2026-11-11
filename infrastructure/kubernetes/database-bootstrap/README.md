# Repeatable database setup for the lab

After Terraform apply and kubeconfig setup, run from the repository root:

```bash
python3 scripts/bootstrap-database.py
```

Requires Python 3, Terraform, AWS CLI, kubectl, curl, an active `production` AWS session,
and context `order-platform-prod` pointing at the recreated cluster. RDS must be
available and the EKS-to-RDS security-group rule must be in place.
The helper explicitly checks AWS account and cluster endpoint before writes.
It is intentionally for the current prod environment, not a generic multi-account tool.

## What happens

1. Read the current database hostname and administrator secret ARN from Terraform.
2. Retrieve the administrator credentials into memory, without displaying them.
3. Download AWS's public London-region RDS CA bundle and create `rds-ca` ConfigMap.
4. Generate an application password, or reuse the existing app Secret's password.
5. Start a short-lived Job in namespace `order-platform-prod`. It receives temporary
   administrator credentials through a Kubernetes Secret, with no AWS role/token.
6. Connect to private RDS using TLS with hostname and certificate verification.
7. Create/update `ordersapp`, grant access to `orders` and the public schema, then
   verify an actual application login and non-administrator role attributes.
8. Create/update `order-service-secrets` with `DATABASE_URL` and `APP_PASSWORD`.
9. Delete the Job, its setup ConfigMap and temporary administrator Secret.

No password is written to Git, command arguments, a local file or script output.
Secrets still exist in Kubernetes and in process memory; cluster operators with
Secret access can read them. Do not enable shell/SQL tracing or publish DB logs.
If interrupted abruptly, follow the cleanup instructions below.

## What each file does

- job.yaml: the temporary pod, volumes, resource settings and completion behaviour.
- setup.sql: the PostgreSQL user and grants. It does not create the app's tables.
- ../../../scripts/bootstrap-database.py (repository scripts folder): orchestrates
  outputs, secrets, the Job, completion checking and cleanup.

The Job retries no failed runs automatically, stops after four minutes and has a
TTL fallback. The helper waits up to five minutes and removes its resources.
A manual rerun is safe after a completed or failed run; do not run concurrently.
It reuses an existing application password rather than rotating it on every run.

## What this does NOT finish

The app is not installed. Helm must use the same namespace as the generated Secret:

```bash
helm template order-platform infrastructure/helm/order-platform \
  -f infrastructure/helm/order-platform/values-prod.yaml \
  --namespace order-platform-prod
```

The order Deployment mounts `rds-ca` at the path embedded in DATABASE_URL. SQS pod
IAM and the gateway JWT Secret are still separate work; this is not a full deployment.

All database clients currently share a database and some query each other's tables.
The initial `ordersapp` role is deliberately shared at application level, not a
separate least-privilege identity per service. It can create schema objects because
the current apps create tables/indexes at startup. It cannot create databases or
roles and is not an RDS administrator. Before production, split migrations from
runtime privileges and design per-service database grants. Existing objects owned
by a different user may require an ownership migration; this script does not take
ownership or grant administrator privileges to work around that.

Rerunning after destroy creates the login again; it does not restore destroyed data.
The order application's startup code creates its tables. The client Job uses
`postgres:16` like the manual toolbox example; pin a reviewed digest for production.
RDS-managed administrator rotation does not rotate the separate application password.
Refresh the CA bundle by rerunning when AWS updates its trust certificates.

## Cleanup

The helper cleans up its own Job and administrator Secret on normal failures.
If killed abruptly, list resources with `kubectl --context order-platform-prod
-n order-platform-prod get jobs,secrets,configmaps` and delete the matching
`db-bootstrap-...` Job, Secret and ConfigMap. Job TTL does not delete standalone Secrets.
Do not delete `order-service-secrets` or `rds-ca`: the app will need them.
The earlier manual `db-client` pod is independent and can be deleted separately.

## References

- [Kubernetes Jobs](https://kubernetes.io/docs/concepts/workloads/controllers/job/)
- [RDS TLS and CA bundles](https://docs.aws.amazon.com/AmazonRDS/latest/UserGuide/UsingWithRDS.SSL.html)
- [psql variables and SQL scripts](https://www.postgresql.org/docs/16/app-psql.html)
