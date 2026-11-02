# Service inventory for EKS

Source review: 22 October 2026. Scope: all nine `services/*/main.go`, Dockerfiles, dashboard UI and root Compose file. This is a static code inventory, not evidence of a running deployment. Route registrations and caller paths were compared; runtime checks remain below. See [separate fixes](APPLICATION-FIXES.md).

## Configuration and ports

Defaults below come from Go, not Compose. Empty values passed through `getEnv` also use the fallback. All listeners bind on all interfaces.

### api-gateway

Source: [main.go](../services/api-gateway/main.go).

| Variable | Code default / behaviour |
|---|---|
| `JWT_SECRET` | `change-me-in-production` |
| `ORDER_SERVICE_URL` | `http://order-service:8081` |
| `INVENTORY_SERVICE_URL` | `http://inventory-service:8082` |
| `PAYMENT_SERVICE_URL` | `http://payment-service:8083` |
| `NOTIFICATION_SERVICE_URL` | `http://notification-service:8084` |
| `SHIPPING_SERVICE_URL` | `http://shipping-service:8085` |
| `DASHBOARD_SERVICE_URL` | `http://dashboard-api:8086` |
| `PORT` | `8080` |
| `REDIS_URL` | Unset: no rate limiting. Invalid/unreachable at startup: logs warning and disables limiter. Treat authenticated URL as secret. |

### dashboard-api

Source: [main.go](../services/dashboard-api/main.go).

| Variable | Code default / behaviour |
|---|---|
| `PORT` | `8086` |
| `DATABASE_URL` | Required; startup exits if missing. Secret: PostgreSQL connection string. |

### inventory-service

Source: [main.go](../services/inventory-service/main.go).

| Variable | Code default / behaviour |
|---|---|
| `PORT` | `8082` |
| `DATABASE_URL` | Required; startup exits if missing. Secret: PostgreSQL connection string. |

### notification-service

Source: [main.go](../services/notification-service/main.go).

| Variable | Code default / behaviour |
|---|---|
| `PORT` | `8084` |
| `DATABASE_URL` | Required; startup exits if missing. Secret: PostgreSQL connection string. |

### order-service

Source: [main.go](../services/order-service/main.go).

| Variable | Code default / behaviour |
|---|---|
| `PORT` | `8081` |
| `DATABASE_URL` | Required; startup exits if missing. Secret: PostgreSQL connection string. |
| `SQS_QUEUE_URL` | Unset: events logged only; no messages sent. Required for the intended EKS event flow. |

### payment-service

Source: [main.go](../services/payment-service/main.go).

| Variable | Code default / behaviour |
|---|---|
| `PORT` | `8083` |
| `DATABASE_URL` | Required; startup exits if missing. Secret: PostgreSQL connection string. |
| `SQS_QUEUE_URL` | Unset: events logged only; no messages sent. Required for the intended EKS event flow. |

### scheduler

Source: [main.go](../services/scheduler/main.go).

| Variable | Code default / behaviour |
|---|---|
| `HEALTH_PORT` | `8091` |
| `DATABASE_URL` | Required; startup exits if missing. Secret: PostgreSQL connection string. |

### shipping-service

Source: [main.go](../services/shipping-service/main.go).

| Variable | Code default / behaviour |
|---|---|
| `PORT` | `8085` |
| `DATABASE_URL` | Required; startup exits if missing. Secret: PostgreSQL connection string. |
| `SQS_QUEUE_URL` | Unset: events logged only; no messages sent. Required for the intended EKS event flow. |

### worker

Source: [main.go](../services/worker/main.go).

| Variable | Code default / behaviour |
|---|---|
| `INVENTORY_SERVICE_URL` | `http://inventory-service:8082` |
| `PAYMENT_SERVICE_URL` | `http://payment-service:8083` |
| `NOTIFICATION_SERVICE_URL` | `http://notification-service:8084` |
| `SHIPPING_SERVICE_URL` | `http://shipping-service:8085` |
| `ORDER_SERVICE_URL` | `http://order-service:8081` |
| `HEALTH_PORT` | `8090` |
| `SQS_QUEUE_URL` | Required; startup exits if missing. |

## Secrets and production configuration

- Seven DB clients (all except gateway and worker) require `DATABASE_URL`. Compose uses one shared `orders` database and `app` role. Never use `app:localdev` or `sslmode=disable` in production; supply a TLS-verified connection string and managed credentials through Secret references.
- Gateway `JWT_SECRET` must be a strong managed secret. Never deploy `change-me-in-production` (Go fallback) or `local-dev-secret` (Compose). No other service reads JWT secrets or independently verifies tokens.
- No database/JWT secret is needed by worker; gateway has no database credentials. Inventory, notification, scheduler and dashboard have no AWS SDK queue usage.
- Order, payment, shipping and worker use the AWS SDK default credential/config chain. Set `AWS_REGION=eu-west-2` explicitly and use workload identity (Pod Identity or IRSA), not static AWS keys in Helm values. Queue URL is configuration, not a credential. These SDK settings are separate from the explicit application variables listed above.
- Service URL defaults assume matching Kubernetes Service names in the same namespace and matching service ports. Override URLs if chart names/namespaces differ. DB and Redis addresses must be environment-specific.

## API routes and probes

All nine register `/livez` returning 200 without dependency checks. All register `/healthz`; seven DB clients ping PostgreSQL and return 503 on failure, but do not verify tables. Gateway and worker always return OK, even with Redis/SQS/downstream failures. There is no `/readyz`. Use direct pod `/livez` for liveness and `/healthz` as provisional readiness; gateway/worker need stronger readiness (FIX-08). Dashboard also registers `/dashboard/healthz`.

| Service | Default port | Registered business routes (relative to service) | Gateway prefix |
|---|---:|---|---|
| api-gateway | 8080 (`PORT`) | POST `/auth/login`, POST `/auth/register`; proxy fallback `/` | Public entry point |
| order-service | 8081 (`PORT`) | GET/POST `/`; GET `/{id}`; PUT `/status` | `/api/orders` |
| inventory-service | 8082 (`PORT`) | GET/POST `/products`; `/products/{id}`; POST `/reserve`, `/release`; `/low-stock` | `/api/inventory` |
| payment-service | 8083 (`PORT`) | POST `/charge`, `/refund`; `/ledger`; `/balance/{customer}` | `/api/payments` |
| notification-service | 8084 (`PORT`) | POST `/send`; `/history`; `/templates` | `/api/notifications` |
| shipping-service | 8085 (`PORT`) | GET/POST `/shipments`; `/shipments/{id}`; `/track/{tracking}`; POST `/webhook` | `/api/shipping` |
| dashboard-api | 8086 (`PORT`) | Static UI `/`; `/dashboard/summary`, `/dashboard/orders/stats`, `/dashboard/revenue`, `/dashboard/inventory/alerts`, `/dashboard/shipping/overview` | `/api/dashboard` — mismatch, see below |
| worker | 8090 (`HEALTH_PORT`) | Health only | None |
| scheduler | 8091 (`HEALTH_PORT`) | Health only | None |

Routes without a listed verb do not explicitly restrict methods in their handlers; intended use is GET. Order's `/` handler also catches unknown paths. Gateway matches prefixes with `HasPrefix` and strips the full prefix. Static comparison confirms worker's POST/PUT paths exist and match their handlers. Normal gateway paths map correctly for orders, inventory, payment, notification and shipping.

**Dashboard mismatch:** `/api/dashboard/summary` becomes `/summary`, but dashboard registers `/dashboard/summary`. The UI also requests same-origin `/dashboard/*`, `/api/*` and `/auth/login`: serving it only behind gateway fails because gateway does not route `/` or `/dashboard/*`; serving it only on dashboard fails for `/api/*` and `/auth/*`. Define one ingress/path contract and test it (FIX-03). `/api/dashboard/healthz` does reach `/healthz`, so health success will not reveal this business-route bug.

Gateway authentication skips `/api/shipping/webhook` and paths ending `/healthz`. Other proxy routes require a JWT, but there is no role enforcement. Direct downstream access trusts headers or is unauthenticated. Expose only the agreed UI/gateway entry paths; keep other Services internal.

## Database ownership and startup

| Migration owner | Tables created at startup | Other direct users |
|---|---|---|
| order-service | `orders`, `order_events` | scheduler reads/writes orders, deletes order_events; dashboard reads orders |
| inventory-service | `products`, `reservations` | scheduler reads/updates both; dashboard reads products |
| payment-service | `payments`, `ledger_entries` | scheduler reads payments; dashboard reads payments |
| notification-service | `notifications`, `notification_templates` | None; templates seeded at startup |
| shipping-service | `shipments`, `tracking_events` | dashboard reads shipments |
| gateway / worker / scheduler / dashboard | No migrations | scheduler and dashboard require other owners' tables |

These are logical code owners, not isolated schemas: current SQL uses unqualified table names and Compose shares a database. Splitting each service into a separate database would break scheduler/dashboard. Owner services run `CREATE TABLE/INDEX IF NOT EXISTS` on every startup, with no migration history or upgrade tooling. Seven DB clients retry Ping up to 120 times with 1-second sleeps (individual pings have no explicit timeout), then exit. Listener startup follows DB readiness and, for owners, migration completion. Dashboard/scheduler only wait for DB connectivity and can start before tables exist.

Plan ordered, versioned migrations before workloads and separate migration permissions from runtime roles (FIX-09). Max open connections per replica: order/inventory/payment 25 each, notification/dashboard 10 each, shipping 15, scheduler 5: **115 total at one replica each**. Size the database/pool budget for replica counts and rollout surge.

## Dependency and event map

Gateway -> six HTTP services (ports above) and Redis (Compose 6379). Worker -> inventory, payment, notification, shipping, order over HTTP. Seven DB clients -> PostgreSQL (Compose 5432). Order/payment/shipping -> SQS HTTPS; worker <- SQS HTTPS. All pods need DNS; SDK identity may require additional AWS service endpoints. No other outbound application HTTP clients are implemented.

| Producer | Event types | Worker action |
|---|---|---|
| order | `order.created` | reserve inventory -> charge payment -> send confirmation -> confirm order; failure branches release/cancel/notify |
| order | `order.status_changed` | processing: create shipment; shipped/delivered: notify; cancelled: release, refund only if payload has payment_id |
| payment | `payment.completed`, `payment.failed`, `payment.refunded` | completed/failed: log only; refunded: unknown event, skipped |
| shipping | `shipment.created`, `shipment.<webhook status>` | created: log only; delivered: PUT order status delivered; other statuses: skipped |
| scheduler | None | Cancellation/retry comments do not publish messages |

Envelope: `{type, payload, timestamp}`; timestamp is UTC RFC3339. No event ID/schema version. All four queue clients use `SQS_QUEUE_URL`; use the same Standard queue for this single worker orchestration flow. No FIFO message group or deduplication fields are supplied. Publishers call SendMessage; worker calls ReceiveMessage (batch 10, long poll 20 seconds), then DeleteMessage after handler success. Failed parsing/handling leaves a message for redelivery; unknown types are deleted. Empty/error receives also sleep 5 seconds. No visibility extension, deduplication store or explicit per-call publish timeout exists. Provision a DLQ and choose visibility timeout to cover the full multi-call workflow, not just one 10-second HTTP request.

## Inputs to the next phases

| Phase | Inputs / required work |
|---|---|
| CI | Nine independent Go modules and Docker contexts `services/<name>`; dashboard includes embedded `static/`. Build/test/vet each module; run gateway route/auth contracts, real PostgreSQL migrations and queue retry/idempotency integration tests. Tag images by commit SHA. All Dockerfiles force `GOARCH=amd64`: use amd64 EKS nodes or fix multi-architecture builds. Dockerfile comments about non-root are not proof: explicitly enforce runtime UID/security context and verify image metadata. |
| Terraform | ECR repos, EKS workload identities, private PostgreSQL and credentials, Redis if limiter required, Standard queue + DLQ, networking and endpoint/egress access. Producers need queue-scoped SendMessage; worker needs ReceiveMessage/DeleteMessage (ChangeMessageVisibility only if implemented). Supply endpoints/ARNs/secret references as outputs, not secret values in source. |
| Helm | Per-service ports/env/secretRefs from this inventory; explicit AWS region for queue clients; internal service names aligned with URL values; direct HTTP probes, startup budget covering DB/migrations, resources and DB connection limits. Scheduler initially one replica (still requires race fix). API servers use 30-second shutdown contexts: allow termination grace beyond that. Define tested UI routing and restricted backend access. |

## Validation status and remaining acceptance work

- Completed: source inventory of all nine services; explicit env/default extraction; registered probe paths; worker caller method/path comparison; gateway rewrite comparison; table DDL/read/write and queue producer/consumer tracing; Compose build-context existence review.
- Not run: Go builds/tests, container execution, live health/DB outage tests, AWS/SQS delivery, Kubernetes DNS/network policies, or ingress routing. No runtime validation is claimed.
- Compose is not a complete integration environment: it references `localstack:4566` without defining LocalStack or queue creation. Queue clients also need region/auth/endpoint configuration. A queue URL alone is not evidence of working local AWS emulation (FIX-10).
- To close the ticket: run all nine builds/tests; run migrations against an empty DB; verify every direct probe returns 200 and DB probes return 503 on outage; exercise each gateway business route and UI; test order -> reservation -> payment -> confirmation and cancellation/shipping paths against a queue; verify redelivery causes no duplicate side effects and DLQ behaviour. Record commands/results in this document. Resolve blockers or link accepted scope decisions before claiming production readiness.
