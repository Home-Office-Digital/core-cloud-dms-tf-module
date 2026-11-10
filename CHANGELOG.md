# Changelog

All notable changes to this project will be documented in this file.
Semantic versioning (https://semver.org/) must be adhered to for all Core Cloud modules.

### [0.2.0] Unreleased

- One-off full-load database migration using DMS Serverless.
- Source and target endpoints using Secrets Manager credentials, `verify-full` SSL against a supplied CA bundle, and a customer managed KMS key.
- DMS role trust limited to the deploying account (`aws:SourceAccount`).
- Security group with egress scoped to the source, the target and the AWS service VPC endpoints.
- IAM role for DMS to read the endpoint secrets, and optional account-level `dms-vpc-role` and `dms-cloudwatch-logs-role`.
- Table mappings generated from `include_schemas`.
- Fixed replication settings: full LOB mode, truncate before load, CloudWatch logging and row-level validation.
- Native Terraform tests with a mock AWS provider.

### [0.1.0] 2026-11-09

- Repository skeleton: CI workflows (Terraform validate, fmt, test, TFLint, Checkov, SonarQube), semantic versioning workflows, Dependabot, CODEOWNERS, contributing guide, code of conduct and provider requirements.
