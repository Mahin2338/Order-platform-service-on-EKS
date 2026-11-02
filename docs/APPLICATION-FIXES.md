# Application fixes discovered during inventory

Separate, issue-ready follow-ups; these are local drafts, not issues created in an external tracker. No application code was changed. See [inventory](SERVICE-INVENTORY.md) for deployment inputs.

## FIX-01: Replace demo authentication and enforce authorization

Priority: Blocker for public/production access.

Evidence: [source](../services/api-gateway/main.go). handleLogin accepts any decoded email/password; register persists no user. Downstream handlers have no role checks; getOrder does not scope lookup to the authenticated customer. UI auto-logs in with admin@platform.local/admin.

Acceptance: Implement verified identity, reject missing/default JWT secret at startup, enforce customer ownership and privileged operations, strip untrusted identity headers and restrict direct backend access. Tests must reject arbitrary credentials, cross-customer reads and customer access to administrative actions.

## FIX-02: Authenticate carrier webhooks

Priority: Blocker for public/production access.

Evidence: [source](../services/shipping-service/main.go). handleCarrierWebhook accepts unsigned status updates; gateway explicitly exempts its route from JWT authentication.

Acceptance: Verify carrier signature and timestamp, prevent replay, validate allowed status transitions, and commit tracking/status atomically. Invalid or replayed requests must not update shipments or publish events.

## FIX-03: Fix dashboard UI and gateway routing contract

Priority: Blocker for UI rollout.

Evidence: [source](../services/api-gateway/main.go). Gateway strips /api/dashboard but dashboard handlers retain /dashboard. UI uses same-origin /dashboard/*, /api/* and /auth/*; neither service alone serves that full contract.

Acceptance: Choose canonical paths and implement gateway/ingress routing consistently. Remove demo auto-login. Test UI asset loading, authenticated summary/revenue and all service API calls through the actual public entry point.

## FIX-04: Make event publication durable

Priority: Blocker for reliable order processing.

Evidence: [source](../services/order-service/main.go). Order/payment/shipping commit DB work then send events; absent queue or SendMessage failure is only logged and HTTP can still report success.

Acceptance: Use a transactional outbox with retrying delivery, fail fast on missing production queue configuration, bound SDK calls and redact sensitive payload logs. Test queue outage and recovery without lost events.

## FIX-05: Make worker side effects idempotent and failures retryable

Priority: Blocker for reliable order processing.

Evidence: [source](../services/worker/main.go). Multi-step workflow can reserve/charge again after retry. Some compensation/notification failures are ignored; inventory/payment failures can return nil, causing deletion even when cancellation fails. No stable event ID or idempotency key.

Acceptance: Add stable event IDs and durable operation deduplication, validate payloads, distinguish business rejection from transient failures and persist workflow progress. Replay an event and inject a failure after each step; no duplicate charge/reservation/shipment and no lost compensation is allowed.

## FIX-06: Complete order, refund and shipment lifecycle

Priority: Blocker for complete business flow.

Evidence: [source](../services/worker/main.go). No automated confirmed -> processing transition. Shipment creation/in_transit does not mark order shipped; delivered only permits transition from shipped. Cancel events from order omit payment_id, so worker refund branch is skipped. Worker creates shipments with Unknown addresses, UNKNOWN postcode and fixed GB/1kg.

Acceptance: Define lifecycle ownership, persist genuine delivery details and payment linkage, implement intermediate transitions and reliable cancellation/refund. Test end-to-end confirmed -> processing -> shipped -> delivered plus cancellation after charge.

## FIX-07: Fix inventory concurrency and scheduler correctness

Priority: Blocker before concurrent processing.

Evidence: [source](../services/scheduler/main.go). Expiry selects active reservations outside a locking transaction and ignores SQL/commit errors; concurrent schedulers/releases can decrement twice. detectAbandonedOrders directly cancels without event emission or guarded status update. Inventory release likewise reads active rows without locks. Reservations never become consumed/committed after successful purchase.

Acceptance: Make reserve/release/expire/consume atomic and idempotent; serialize scheduled execution and check all errors. Publish durable cancellation events. Define reservation completion semantics. Test concurrent release/expiry, repeated reserve, purchase completion and scheduler restarts.

## FIX-08: Implement meaningful readiness and bounded dependency checks

Priority: Required before relying on production probes.

Evidence: [source](../services/worker/main.go). Gateway/worker /healthz always succeeds; scheduler only checks DB, not job health/schema. DB Ping has no explicit context deadline. Worker/scheduler ignore health listener startup errors.

Acceptance: Use bounded dependency checks and worker loop/job status, fail on listener errors and add a startup probe budget. Test missing schema, revoked SQS permissions, stopped polling and DB outage. Keep liveness independent of remote dependency health.

## FIX-09: Introduce controlled schema migrations and runtime DB roles

Priority: Required before production schema evolution.

Evidence: [source](../services/order-service/main.go). Five owners run unversioned CREATE IF NOT EXISTS at startup; scheduler/dashboard can run before tables exist. Shared DB dependencies prohibit blindly provisioning one isolated DB per service.

Acceptance: Choose shared-schema access boundaries, add versioned migrations with a single controlled runner and establish least-privilege runtime grants. Test fresh install and upgrade before scheduler/dashboard readiness. Check every SQL Exec/Scan/Commit/rows.Err, including currently ignored payment ledger writes and notification inserts.

## FIX-10: Repair local SQS integration for reproducible CI

Priority: Blocker for claimed integration validation.

Evidence: [source](../services/worker/main.go). Compose references localstack but defines neither it nor queue provisioning. AWS region/credentials and a tested SDK endpoint override are absent.

Acceptance: Add an explicit emulator and queue setup plus verified SDK configuration, or provide isolated AWS integration fixtures. Run publish -> receive -> side effect -> delete and retry/DLQ tests before marking network validation complete.

## FIX-11: Replace simulated payment, notification and shipping integrations

Priority: Blocker for real customer transactions; acceptable only in explicitly labelled demo.

Evidence: [source](../services/payment-service/main.go). Payments randomly fail 10% and never call a processor. Notifications mark sent without delivery, do not render template placeholders, and ignore insertion errors. Shipping fabricates tracking IDs and 3–7 day estimates without calling a carrier.

Acceptance: Implement real adapters with managed credentials, deterministic test doubles and honest success/error reporting; render templates against a validated payload contract. If retaining demo scope, explicitly prohibit real transactions and label simulated operations.

## FIX-12: Validate financial and inventory inputs

Priority: Blocker for real customer transactions.

Evidence: [source](../services/order-service/main.go). Order totals trust customer-supplied float prices/quantities; inventory permits invalid quantities; payment refund read/update is not concurrency protected.

Acceptance: Use authoritative prices and integer minor units/decimal arithmetic, validate positive quantities and permitted currency/amounts, enforce database constraints and serialize refunds. Test tampered prices, negative quantities, concurrent refunds and currency aggregation (dashboard currently hardcodes GBP).

## FIX-13: Harden rate limiter and container deployment assumptions

Priority: Required production hardening.

Evidence: [source](../services/api-gateway/main.go). Limiter silently disables on startup Redis failure and ignores runtime Redis errors; limit is fixed at 1000/minute and client headers are trusted. Dockerfiles force amd64 and contain non-root comments without explicit USER declarations.

Acceptance: Define fail-open/fail-closed policy, trusted proxy handling and configurable limits. Pin node architecture or publish multiarch images; verify final image UID and enforce non-root Kubernetes security context. Exercise Redis failure and build/run on target node architecture.
