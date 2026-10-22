# Production Terraform setup

This environment uses the AWS provider and an S3 remote backend with encryption
and native S3 state locking. No DynamoDB table is required.

The state bucket must exist before initializing this environment. Enable bucket
versioning, block public access, and enable default server-side encryption.

1. Configure AWS authentication using your normal AWS CLI profile or SSO session.
   If using a named profile, export `AWS_PROFILE=your-profile` so both the backend
   and provider use it. Do not put credentials in Terraform files.
2. From this directory, copy `backend.hcl.example` to `backend.hcl` and
   `terraform.example.tfvars` to `terraform.tfvars`. Replace the placeholders;
   use the same region in both files. Set `prod_account_id` in `terraform.tfvars`
   to the intended production account's 12-digit ID. The AWS provider rejects
   credentials for any other account. This check applies to the provider, not
   the separately configured S3 backend or bootstrap root.
3. Verify the intended account and initialize:

   ```bash
   aws sts get-caller-identity
   terraform init -backend-config=backend.hcl
   terraform validate
   terraform plan
   ```

Commit the generated `.terraform.lock.hcl` for repeatable provider installation.
The local configuration files and Terraform state are ignored by Git.

The AWS identity needs access to the state bucket and state object, plus
GetObject, PutObject, and DeleteObject on the associated `.tflock` object.
Application infrastructure modules have not yet been wired into this environment.
