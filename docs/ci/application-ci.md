# Application CI

Workflow: [application-ci.yml](../../.github/workflows/application-ci.yml).

## Execution order

1. Detect affected service directories. Pull requests use the PR's changed files;
   pushes to `main` compare against the previous main commit. Workflow changes
   select all nine services. Docs-only or infrastructure-only changes select none.
2. For each selected service, check formatting, download/verify dependencies,
   run `go vet` and `go test -race`, then run `govulncheck`.
3. Scan the service's dependency inventory with Trivy, build its Linux amd64
   Docker image, verify its explicit non-root user and scan the image for
   vulnerabilities and secrets.
4. The stable `Application CI gate` succeeds only if all selected service checks
   succeed, or change detection confirms there are no affected services.
5. On pushes to `main` only, after the shared gate passes and the `ecr-publish`
   environment permits it, download and push the exact scanned images to ECR.
   Pull requests have no AWS role or image-publishing permission.
6. Report the release version tag and registry digest. Save a JSON image reference artifact
   per published service. Deployment/promotion is deliberately outside this workflow.

Services are independent Go modules and Docker build contexts. A future shared
library or shared build script must be added to the affected-service filters.
Removing a whole service directory requires updating its filter too; otherwise
its check fails safely because its build context no longer exists.

## Blocking policy

- Formatting, dependency verification, vet, tests and reachable Go vulnerability
  findings must pass. A service with no tests is not behaviourally verified just
  because `go test` exits successfully.
- Trivy blocks HIGH and CRITICAL OS/library vulnerabilities, including unfixed
  findings. The image scan also checks secrets at those severities.
- Scanner/database download errors fail the check. There are no `continue-on-error`
  exceptions or vulnerability suppression files configured by this change.
- Reports produced before a failure are retained as workflow artifacts for seven
  days. Later steps do not run after earlier failures. No scan success is inferred
  for steps that were skipped.
- `govulncheck` checks reachable vulnerable Go code, while Trivy's dependency
  inventory also catches known vulnerable dependencies that might not be reachable.
- Database findings change over time even when source code is unchanged. Fix code,
  dependencies or base-image pins when findings block CI; don't silently weaken gates.

## GitHub setup required before publishing

1. Create a GitHub environment named **ecr-publish**. Restrict its deployment
   branches to **main only**. This environment gates artifact publishing, not an
   application deployment. Optionally require a reviewer before publishing.
2. Protect `main` with a repository ruleset: require PRs and the status check
   **Application CI gate**, prohibit force pushes/deletion, and restrict bypasses.
   The workflow cannot distinguish an authorised merge from a direct push to main;
   repository rules must prevent unapproved direct pushes. Without these controls,
   do not claim publishing is restricted to permitted merges.
3. Configure these environment variables:

   | Variable | Value |
   |---|---|
   | `AWS_ACCOUNT_ID` | `792289066018` |
   | `AWS_REGION` | `eu-west-2` (also the workflow fallback) |
   | `AWS_ROLE_ARN` | IAM role ARN trusted for this GitHub environment |
   | `ECR_REPOSITORY_PREFIX` | `order-platform` (also the fallback) |

   These identifiers are not credentials. Do not add AWS access keys as secrets.
4. Permit the referenced GitHub/Docker/AWS/Trivy actions in the repository's Actions
   settings. Actions currently use release tags; review and pin commit SHAs if your
   organisation requires immutable third-party action dependencies.

## AWS setup required before publishing

The ECR Terraform module defines nine separate immutable repositories, wired
into production. They have not been created in AWS by this change. The workflow
does not create repositories or IAM resources.

```text
order-platform/api-gateway
order-platform/dashboard-api
order-platform/inventory-service
order-platform/notification-service
order-platform/order-service
order-platform/payment-service
order-platform/scheduler
order-platform/shipping-service
order-platform/worker
```

Each service uses its own VERSION file, initially `1.0.0`, as its published image
tag. For example, `order-platform/order-service:1.0.0` and
`order-platform/worker:1.0.0` are independent releases.

Every repository must use **IMMUTABLE** tags without exclusions. The workflow
refuses to publish otherwise. Git commit IDs remain in internal build/artifact
identifiers and release metadata, not public release tags. Deployment should use
the reported `repository@sha256:...` reference. There is no `latest` tag.

Create the GitHub OIDC provider `token.actions.githubusercontent.com` with audience
`sts.amazonaws.com` if not already present. The publishing role trust must match:

- Audience: `sts.amazonaws.com`
- Subject: `repo:Mahin2338/Order-platform-service-on-EKS:environment:ecr-publish`

Because environment-based subjects do not encode the branch, the environment's
main-only restriction is essential. Do not use a wildcard repository/subject.
Grant this role only:

- `ecr:GetAuthorizationToken` on `*` (this API requires it).
- `ecr:DescribeRepositories`, `ecr:DescribeImages`, `ecr:BatchCheckLayerAvailability`,
  `ecr:InitiateLayerUpload`, `ecr:UploadLayerPart`, `ecr:CompleteLayerUpload`,
  `ecr:PutImage`, and `ecr:BatchGetImage` on the nine repository ARNs above, each in account `792289066018`, region
  `eu-west-2` (for example, `arn:aws:ecr:eu-west-2:792289066018:repository/order-platform/order-service`).

It does not need cluster access, Terraform permissions, repository creation,
image deletion or AWS administrator access. Never reuse the human SSO admin role
as the GitHub publishing role.

## Artifacts, retries and limitations

- On main builds, scanned Docker archives are retained for one day, transferred
  within the same workflow run, then loaded by the publishing job without running
  source code or rebuilding it. PR builds do not upload image archives.
- Published-reference JSON artifacts are retained for 30 days. ECR retention is a
  separate lifecycle-policy decision.
- All service checks must finish before publishing starts. Publishing itself is
  not transactional across services: one upload can succeed while another
  fails. The summary/artifacts identify successful uploads. Nothing auto-deploys.
- Re-running publishing for an existing immutable version tag can fail because
  overwriting is intentionally forbidden. Inspect existing digest references before
  retrying; don't delete or mutate tags merely to make a rerun pass.
- This pipeline checks builds/scans, not the complete running order workflow.
  Runtime tests with PostgreSQL/SQS are a separate task.
- The nine Dockerfiles and `.dockerignore` changes from the previous task remain
  in the working tree. CI expects their explicit `65532:65532` runtime user.

## Validation status

Passed locally: `actionlint`, YAML parsing, all nine build-context checks,
and selection checks for one service, multiple services, dotfiles, docs-only
changes and shared workflow changes. No local image builds were run for this
workflow. End-to-end runner execution, scan results, OIDC authentication and ECR
pushes remain unverified
until this workflow is committed/pushed and the prerequisites above are configured.

## Release versions

Each service starts with a `VERSION` file containing `1.0.0`. Before releasing a
new build of that service, update its version, for example to `1.0.1` for a patch.
The workflow validates the simple `MAJOR.MINOR.PATCH` format. Prerelease/build
suffixes are not currently accepted. It does not automatically increment versions.

A workflow change selects all services, so publishing a rebuild requires unused
versions for all selected services. Reusing a published version intentionally fails
rather than overwriting the existing release. PR checks do not need ECR access;
version collisions are detected by immutable ECR publishing, not by PR scans.

The checked VERSION value travels with the scanned image artifact. The publish job
does not reread it from a newer branch checkout. A release reference looks like:
`792289066018.dkr.ecr.eu-west-2.amazonaws.com/order-platform/order-service:1.0.0`.

To create only the repositories while VPC/EKS changes are pending, initialise production
and review a saved plan targeted at `module.ecr`. Verify it contains only the nine
repository creations before applying that saved plan. Targeting is an exceptional
partial operation, not the normal deployment workflow. Run a full plan afterwards
to see remaining infrastructure changes. Do not run an unrestricted apply merely
to create the repositories.
