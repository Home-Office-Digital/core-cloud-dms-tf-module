# Changelog

All notable changes to this project will be documented in this file.
Semantic versioning (https://semver.org/) must be adhered to for all Core Cloud modules.

### [0.3.0] Unreleased
- Endpoints and serverless compute use the AWS managed `aws/dms` key. With a customer managed key, provisioning failed with `KMSKeyNotAccessibleFault`, because the DMS Serverless service-linked role's session policy does not allow it. `kms_key_arn` now only covers decrypting the endpoint secrets.
- Upgrading from 0.2.0 replaces the endpoints and the replication.

### [0.2.0] 2026-11-10

- One-off full-load database migration using DMS Serverless.
- Source and target endpoints using Secrets Manager credentials, `verify-full` SSL against a supplied CA bundle, and a customer managed KMS key.
- DMS role trust limited to the deploying account (`aws:SourceAccount`).
- Optional `permissions_boundary_arn` for the module's IAM roles.
- Security group with egress scoped to the source, the target and the AWS service VPC endpoints.
- IAM role for DMS to read the endpoint secrets, and optional account-level `dms-vpc-role` and `dms-cloudwatch-logs-role`.
- Table mappings generated from `include_schemas`.
- Fixed replication settings: full LOB mode, truncate before load, CloudWatch logging and row-level validation.
- Native Terraform tests with a mock AWS provider.

### [0.1.0] 2026-11-09

- Repository skeleton: CI workflows (Terraform validate, fmt, test, TFLint, Checkov, SonarQube), semantic versioning workflows, Dependabot, CODEOWNERS, contributing guide, code of conduct and provider requirements.
