# Build your RDS module

This is your configuration worksheet. Choose the settings first, then write the
Terraform in small steps. **The module is connected to prod configuration, but has not been applied or connection-tested.**

We use the community-maintained [terraform-aws-modules/rds/aws module, version 7.2.2](https://registry.terraform.io/modules/terraform-aws-modules/rds/aws/7.2.2).
It creates AWS resources for us; we still choose how the database should behave.

## How to use this worksheet

Work through **one section at a time**:

1. Fill in your choices and a short reason.
2. Explain what you expect AWS to create.
3. Write those settings in `main.tf` yourself.
4. Ask for a review before moving on.

After the module is wired into prod, use `terraform validate` and review a
`terraform plan` before applying. A valid configuration does not prove the app
can connect; we test that after deployment.

The tables cover the main choices for this application. You do not need to set
every input: the upstream module has defaults. Its [complete input list](https://github.com/terraform-aws-modules/terraform-aws-rds/blob/v7.2.2/variables.tf)
is the reference for additional settings and exact defaults.

## 1. What database are we creating?

| Setting | Meaning and choices | Your choice |
| --- | --- | --- |
| `identifier` | AWS name for the RDS instance, such as `order-platform-prod`. | |
| `engine` | Database software. Our application uses PostgreSQL: `postgres`. Changing to MySQL would require application changes. | |
| `engine_version` | PostgreSQL version. Local development uses PostgreSQL 16; check that your chosen version is available in the AWS region. This is separate from Terraform module version `7.2.2`. | |
| `db_name` | Initial database inside PostgreSQL. Our current services share `orders`; some services query tables created by other services. | |
| `port` | PostgreSQL normally listens on `5432`. | |

**Your reason:**

## 2. How powerful should it be?

| Setting | Meaning and choices | Your choice |
| --- | --- | --- |
| `instance_class` | CPU and RAM for the database server. Smaller burstable classes suit experiments; larger classes handle more work. Check engine/region compatibility before choosing. | |
| `allocated_storage` | Starting disk capacity in GiB. This is separate from server size. | |
| `storage_type` | Disk type. `gp3` is a sensible starting point; provisioned-IOPS options are for more demanding workloads. | |
| `max_allocated_storage` | Optional storage autoscaling ceiling. Storage can grow, but does not automatically shrink afterwards. | |
| `iops`, `storage_throughput` | Optional disk performance tuning. Leave these alone initially unless the workload needs more performance; valid values depend on engine, disk type and size. | |

Our services can open multiple database connections. Their current combined pool
limits are 115 connections for one replica of each database-using service. That
is a configured ceiling, not a claim that 115 connections will always be active.
We must check connection capacity and actual memory use before assuming the
smallest instance is sufficient.

**Your reason:**

## 3. Where does it live, and who can reach it?

| Setting | Meaning and choices | Your choice |
| --- | --- | --- |
| `create_db_subnet_group` | Whether this module creates the group of subnets RDS may use. | |
| `subnet_ids` | Private subnet IDs for a new DB subnet group. Provide subnets across at least two AZs, even for a Single-AZ database. | |
| `db_subnet_group_name` | Use this when referring to an existing DB subnet group instead. | |
| `publicly_accessible` | Whether RDS can be publicly reachable. Use `false` for our app; pods connect through the VPC. | |
| `vpc_security_group_ids` | Attach database firewall rules. Create a separate security group allowing PostgreSQL traffic from the intended EKS workload source, initially the worker-node security group. Do not allow port 5432 from the internet. | |
| `multi_az` | `false`: one database instance, cheaper for a lab. `true`: a standby in another AZ for failover, with extra cost. The standby is not a read replica. | |
| `availability_zone` | Optional placement for a Single-AZ instance. Usually let AWS choose. | |

The RDS module does not create our database security group. We must create it and
pass its ID. A NAT gateway is not required for pod-to-RDS traffic within the VPC.

**Your reason:**

## 4. Credentials and encryption

| Setting | Meaning and choices | Your choice |
| --- | --- | --- |
| `username` | Initial administrator username. Applications should later use a separate database user with limited permissions. | |
| `manage_master_user_password` | Let RDS generate and store the administrator password in Secrets Manager. This avoids writing that password into Terraform configuration. | |
| `master_user_secret_kms_key_id` | Optional customer-managed encryption key for that secret. Usually unnecessary for our first setup. | |
| `storage_encrypted` | Encrypt the database disks. Use `true`. | |
| `kms_key_id` | Optional customer-managed key for disk encryption. Otherwise use the applicable AWS-managed key. | |
| `iam_database_authentication_enabled` | Optional IAM-based database login. It needs additional IAM and application configuration; it is separate from Secrets Manager password retrieval. | |

Disk encryption does not encrypt network traffic. Configure PostgreSQL clients
for TLS and certificate verification when connecting to RDS. Do not copy the
local development `sslmode=disable` setting into production.

The app will need a database hostname, port, database name and credentials.
Creating an RDS secret does not automatically deliver credentials to a pod.
We will configure that connection separately; do not put passwords in this README.

**Your reason:**

## 5. Backups and nightly teardown

| Setting | Meaning and choices | Your choice |
| --- | --- | --- |
| `backup_retention_period` | Days of automated backup retention. For PostgreSQL, `0` disables automated backups; choose a positive value if you want recovery history. | |
| `backup_window` | Preferred daily backup window, in UTC. | |
| `deletion_protection` | `true` blocks deletion until disabled. Useful protection, but prevents your usual nightly destroy. | |
| `skip_final_snapshot` | `false` requests a final snapshot on deletion. `true` skips that final recovery copy. | |
| `final_snapshot_identifier_prefix` | Naming prefix used by the module for the final snapshot. | |
| `delete_automated_backups` | Whether automated backups are removed when the database is deleted. Treat this separately from final snapshots. | |
| `copy_tags_to_snapshot` | Copy database tags onto snapshots for identification. | |
| `snapshot_identifier` | Restore an instance from an existing snapshot instead of starting empty. | |

**Destroying and recreating RDS does not automatically restore your data.** If you
keep a final snapshot, restoring it is an explicit step. Retained snapshots also
have storage costs. Choose the teardown behaviour before the first deployment.

**Your reason:**

## 6. Updates, logs and optional tuning

These can wait until the first five sections are understood.

| Setting | What it controls | Your choice |
| --- | --- | --- |
| `maintenance_window` | Preferred weekly maintenance window, in UTC. | |
| `auto_minor_version_upgrade` | Whether AWS can apply eligible minor engine upgrades during maintenance. | |
| `allow_major_version_upgrade` | Whether a requested major engine upgrade is permitted. This does not itself select a new version. | |
| `apply_immediately` | Apply eligible changes immediately rather than waiting for maintenance. Some changes can interrupt service. | |
| `family`, `parameters` | PostgreSQL parameter-group family and server settings. The family must match the selected engine major version. | |
| `create_db_option_group` | Option groups are not used for PostgreSQL; disable creation for this setup. | |
| `enabled_cloudwatch_logs_exports` | Which supported database logs to send to CloudWatch. Log storage has a cost. | |
| `monitoring_interval`, `create_monitoring_role` | Enhanced Monitoring frequency and its required IAM role. | |
| `tags` | Labels such as project and environment for finding resources and tracking costs. | |

For monitoring, performance analysis, secret rotation, replicas, restore methods
and other advanced inputs, use the complete version-pinned input list above.
We can add them when there is a concrete need.

## What each local file is for

- `main.tf`: calls the remote module and supplies settings.
- `variables.tf`: declares values this wrapper accepts from the environment.
- `outputs.tf`: exposes values such as the endpoint and secret ARN to callers.
- `versions.tf`: declares Terraform and provider compatibility.

Keep reusable inputs in this module. Environment-specific choices can be written
explicitly in the prod module call when we connect it.

## Official references

- [Module PostgreSQL example](https://github.com/terraform-aws-modules/terraform-aws-rds/blob/v7.2.2/examples/complete-postgres/main.tf)
- [RDS networking and subnet groups](https://docs.aws.amazon.com/AmazonRDS/latest/UserGuide/USER_VPC.WorkingWithRDSInstanceinaVPC.html)
- [Multi-AZ instance deployments](https://docs.aws.amazon.com/AmazonRDS/latest/UserGuide/Concepts.MultiAZSingleStandby.html)
- [RDS-managed passwords in Secrets Manager](https://docs.aws.amazon.com/AmazonRDS/latest/UserGuide/rds-secrets-manager.html)
- [RDS storage options](https://docs.aws.amazon.com/AmazonRDS/latest/UserGuide/CHAP_Storage.html)
- [Deleting an RDS instance and retaining data](https://docs.aws.amazon.com/AmazonRDS/latest/UserGuide/USER_DeleteInstance.html)

## Current wiring

Prod supplies the instance name, `db.t4g.small` size, VPC, private subnets and
EKS worker security group. The RDS module creates a database security group with
TCP 5432 ingress from that worker group only. No outbound rules are configured;
security groups allow response traffic automatically. This assumes the current
managed-node setup without custom launch-template security groups.

Environment-specific database settings are inputs declared in `variables.tf`;
prod supplies their values in its `module "rds"` call. PostgreSQL, gp3 storage,
private access, port 5432, encryption and managed passwords remain module rules. Backups and final
snapshots are disabled: destroying this lab database discards its data.
The maintenance window is Sunday 00:00–01:00 UTC.

Outputs expose the hostname and administrator secret ARN, not its password.
Application users, secret delivery to pods, TLS configuration and connection tests
are still separate deployment work. Instance capacity and regional availability
must be checked before deployment.
