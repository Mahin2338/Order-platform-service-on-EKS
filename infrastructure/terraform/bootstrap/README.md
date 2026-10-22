# Create the Terraform state bucket

This root uses local state because the remote bucket does not exist yet.
Keep its generated terraform.tfstate securely; it is ignored by Git.

After configuring AWS authentication, run from this directory:

```bash
aws sts get-caller-identity
terraform init
terraform plan
terraform apply
```

The bucket name includes your AWS account ID. It has versioning, encryption,
public access blocking, and Terraform deletion protection.

After apply succeeds, generate the production backend settings:

```bash
printf 'bucket = "%s"\nregion = "eu-west-2"\n' "$(terraform output -raw state_bucket_name)" > ../environments/prod/backend.hcl
cd ../environments/prod
terraform init -backend-config=backend.hcl
terraform validate
terraform plan
```

Production state is remote; bootstrap state remains local. No EKS resources
are created by this bootstrap configuration.
