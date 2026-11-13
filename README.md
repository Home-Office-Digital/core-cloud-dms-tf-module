# Core Cloud DMS Terraform Module

Use this module to migrate a database into a Core Cloud account, for example from ACP RDS, with AWS Database Migration Service (DMS).

It runs a one-off full load using DMS Serverless. Change data capture (CDC), other engines and provisioned replication instances are not supported yet.

This module includes the following checks and scans: Terraform validate, Terraform fmt, Terraform test, TFLint, Checkov, SonarQube and semantic versioning (MAJOR.MINOR.PATCH).

## What it creates

- A DMS Serverless full-load replication that does not start on apply
- Source and target endpoints, using Secrets Manager credentials and SSL with full certificate and hostname verification (`verify-full`)
- A security group allowing DMS outbound only to the source, the target and the Secrets Manager and KMS VPC endpoints
- An IAM role that lets DMS read the two endpoint secrets
- The account-level `dms-vpc-role` and `dms-cloudwatch-logs-role`, unless you turn them off
- A DMS replication subnet group

## Before you start

Only PostgreSQL endpoints are supported in this release.

You need:

- **Network access to the source.** The source database must allow inbound 5432 from `subnet_ids`. For ACP RDS, ask ACP to add the subnet CIDRs to the RDS security group.
- **A target database** that allows inbound 5432 from `subnet_ids`, with the target database already created. With `core-cloud-rds-tf-module`, set `database_name` and `allowed_cidr_blocks`.
- **A customer managed KMS key** for the two secrets. Use `core-cloud-kms-tf-module` if you do not have one.
- **The CA bundle** that signed both database certificates, as PEM. For RDS, download the AWS [global bundle](https://truststore.pki.rds.amazonaws.com/global/global-bundle.pem) and pass it with `file()`.
- **Two Secrets Manager secrets**, one for the source and one for the target, each with `host`, `port`, `username` and `password`. RDS-managed master user secrets cannot be used, because they do not include `host` and `port`.
- **A primary key or unique index** on every source table. Full LOB mode needs one for tables with LOB columns (such as `bytea` and `text`), and validation skips any table without one.
- **No partitioned tables** in the selected schemas. Selecting a whole schema includes partition parents and their child partitions, which duplicates rows on the target.

## Usage

```hcl
module "systems_register_dms" {
  source = "git::https://github.com/Home-Office-Digital/core-cloud-dms-tf-module.git?ref=<tag>"

  name        = "systems-register-test"
  kms_key_arn = module.kms.key_arn

  vpc_id                   = "vpc-0123456789abcdef0"
  subnet_ids               = ["subnet-aaa", "subnet-bbb", "subnet-ccc"]
  source_cidr_blocks       = ["10.250.24.0/21"]
  target_security_group_id = "sg-0123456789abcdef0"

  source_database_name = "systemregister"
  target_database_name = "systemregister"
  source_secret_arn    = aws_secretsmanager_secret.dms_source.arn
  target_secret_arn    = aws_secretsmanager_secret.dms_target.arn
  ca_certificate_pem   = file("${path.module}/global-bundle.pem")
  include_schemas      = ["eventstore", "public"]

  tags = {
    cost-centre      = "1709144"
    account-code     = "521835"
    portfolio-id     = "CTO"
    project-id       = "CC"
    service-id       = "systems-register"
    environment-type = "notprod"
    owner-business   = "owner@example.com"
    budget-holder    = "budget@example.com"
  }
}

output "replication_config_arn" {
  value = module.systems_register_dms.replication_config_arn
}
```

This is a full load only, so changes made on the source after a table is copied are not migrated. Before you start, stop writes to the source and let open transactions finish. Keep the source read-only until you have validated the target and cut over.

After apply, start the replication. DMS connects to the source, provisions capacity, then loads the data, so expect a wait before rows start to move:

```bash
aws dms start-replication \
  --replication-config-arn "$(terraform output -raw replication_config_arn)" \
  --start-replication-type start-replication
```

Check progress and row counts with:

```bash
aws dms describe-replication-table-statistics \
  --replication-config-arn "$(terraform output -raw replication_config_arn)"
```

## Replication settings

The replication uses fixed settings that suit a one-off migration:

- **Full LOB mode**, to avoid truncation. Target LOB columns (such as `bytea` and `text`) must temporarily allow `NULL` during the load. Restore and validate any removed `NOT NULL` constraints after loading.
- **Truncate before load**, so a re-run does not duplicate rows and a schema you created ahead of time (for example with Flyway) is kept. PostgreSQL cannot truncate a table that a foreign key references, so drop foreign keys on the target before the load and recreate them afterwards. Disable target triggers too, or they fire on every loaded row and can change the data.
- **CloudWatch logging**
- **Row-level validation**, so you can check completeness with `aws dms describe-replication-table-statistics`

## Encryption

`kms_key_arn` encrypts the two endpoint secrets. The endpoints and the serverless compute use the AWS managed `aws/dms` key. DMS Serverless provisions through `AWSServiceRoleForDMSServerless`, whose session policy does not allow customer managed keys, so adding that role to the key policy does not help. The databases themselves keep their own encryption.

## What DMS does not migrate

DMS moves table data. It does not migrate users, roles, grants, sequence values, or most other objects such as views, functions and triggers. Create the schema on the target first (for example by running your application's migrations), then use DMS for the data. Reset sequences after the load, for example with `setval`.

## Account-level DMS roles

AWS DMS looks up `dms-vpc-role` and `dms-cloudwatch-logs-role` by those exact names, so only one stack per AWS account can own them. If they already exist in the account, set `create_dms_service_roles = false`.

## Requirements

| Name | Version |
|------|---------|
| terraform | >= 1.7.5 |
| aws | >= 6.0.0 |

## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| name | Name of the migration, used to prefix every resource | `string` | n/a | yes |
| tags | Core Cloud mandatory tags | `object` | n/a | yes |
| kms_key_arn | Customer managed KMS key that encrypts the endpoint secrets | `string` | n/a | yes |
| vpc_id | VPC that DMS runs in | `string` | n/a | yes |
| subnet_ids | Private subnets for DMS, at least two Availability Zones | `list(string)` | n/a | yes |
| source_cidr_blocks | CIDR blocks of the source database | `list(string)` | n/a | yes |
| target_security_group_id | Security group of the target RDS instance | `string` | n/a | yes |
| aws_service_cidr_blocks | CIDR blocks of the Secrets Manager and KMS VPC endpoints | `list(string)` | `["10.252.80.0/21"]` | no |
| source_database_name | Database to migrate from | `string` | n/a | yes |
| target_database_name | Database to migrate into. Must already exist | `string` | n/a | yes |
| source_secret_arn | Secret with the source `host`, `port`, `username` and `password` | `string` | n/a | yes |
| target_secret_arn | Secret with the target `host`, `port`, `username` and `password` | `string` | n/a | yes |
| ca_certificate_pem | PEM CA bundle for `verify-full` on both endpoints | `string` | n/a | yes |
| include_schemas | Schemas to migrate, every table included. Must not contain `%` or `_` | `list(string)` | n/a | yes |
| min_capacity_units | Minimum DMS capacity units (1 DCU = 2 GB) | `number` | `1` | no |
| max_capacity_units | Maximum DMS capacity units (1 DCU = 2 GB) | `number` | `4` | no |
| permissions_boundary_arn | Permissions boundary for every role the module creates. Required in Core Cloud tenant accounts | `string` | `null` | no |
| create_dms_service_roles | Create `dms-vpc-role` and `dms-cloudwatch-logs-role` | `bool` | `true` | no |

## Outputs

| Name | Description |
|------|-------------|
| replication_config_arn | Serverless replication ARN, used to start it and check progress |
| security_group_id | Security group attached to the replication |

## Terraform tests

Tests live in `tests/` and use a mock AWS provider, so they make no AWS calls:

```bash
terraform init -backend=false
terraform test
```
