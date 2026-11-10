data "aws_region" "current" {}

data "aws_caller_identity" "current" {}

data "aws_iam_policy_document" "dms_assume_role" {
  statement {
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["dms.amazonaws.com", "dms.${data.aws_region.current.region}.amazonaws.com"]
    }

    # Confused deputy protection: only DMS acting for this account.
    condition {
      test     = "StringEquals"
      variable = "aws:SourceAccount"
      values   = [data.aws_caller_identity.current.account_id]
    }
  }
}

resource "aws_security_group" "this" {
  name        = "${var.name}-dms"
  description = "Outbound access for the ${var.name} DMS replication"
  vpc_id      = var.vpc_id

  tags = merge(local.tags, { Name = "${var.name}-dms" })
}

resource "aws_vpc_security_group_egress_rule" "to_source" {
  for_each = toset(var.source_cidr_blocks)

  security_group_id = aws_security_group.this.id
  description       = "DMS to source database"
  ip_protocol       = "tcp"
  from_port         = local.port
  to_port           = local.port
  cidr_ipv4         = each.value

  tags = local.tags
}

resource "aws_vpc_security_group_egress_rule" "to_target" {
  security_group_id            = aws_security_group.this.id
  description                  = "DMS to target database"
  ip_protocol                  = "tcp"
  from_port                    = local.port
  to_port                      = local.port
  referenced_security_group_id = var.target_security_group_id

  tags = local.tags
}

resource "aws_vpc_security_group_egress_rule" "to_aws_services" {
  for_each = toset(var.aws_service_cidr_blocks)

  security_group_id = aws_security_group.this.id
  description       = "DMS to Secrets Manager and KMS VPC endpoints"
  ip_protocol       = "tcp"
  from_port         = 443
  to_port           = 443
  cidr_ipv4         = each.value

  tags = local.tags
}

resource "aws_iam_role" "secrets_access" {
  name                 = "${var.name}-dms-secrets"
  description          = "Allows DMS to read the ${var.name} endpoint secrets"
  assume_role_policy   = data.aws_iam_policy_document.dms_assume_role.json
  permissions_boundary = var.permissions_boundary_arn

  tags = local.tags
}

resource "aws_iam_role_policy" "secrets_access" {
  name = "${var.name}-dms-secrets"
  role = aws_iam_role.secrets_access.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid      = "ReadEndpointSecrets"
        Effect   = "Allow"
        Action   = ["secretsmanager:GetSecretValue", "secretsmanager:DescribeSecret"]
        Resource = distinct([var.source_secret_arn, var.target_secret_arn])
      },
      {
        Sid      = "DecryptEndpointSecrets"
        Effect   = "Allow"
        Action   = ["kms:Decrypt", "kms:DescribeKey"]
        Resource = [var.kms_key_arn]
      },
    ]
  })
}

# AWS requires these exact names, so only one stack per account can own them.
resource "aws_iam_role" "dms_vpc" {
  count = var.create_dms_service_roles ? 1 : 0

  name                 = "dms-vpc-role"
  description          = "Allows DMS to manage VPC resources for replication"
  assume_role_policy   = data.aws_iam_policy_document.dms_assume_role.json
  permissions_boundary = var.permissions_boundary_arn

  tags = local.tags
}

resource "aws_iam_role_policy_attachment" "dms_vpc" {
  count = var.create_dms_service_roles ? 1 : 0

  role       = aws_iam_role.dms_vpc[0].name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonDMSVPCManagementRole"
}

resource "aws_iam_role" "dms_cloudwatch_logs" {
  count = var.create_dms_service_roles ? 1 : 0

  name                 = "dms-cloudwatch-logs-role"
  description          = "Allows DMS to publish replication logs to CloudWatch Logs"
  assume_role_policy   = data.aws_iam_policy_document.dms_assume_role.json
  permissions_boundary = var.permissions_boundary_arn

  tags = local.tags
}

resource "aws_iam_role_policy_attachment" "dms_cloudwatch_logs" {
  count = var.create_dms_service_roles ? 1 : 0

  role       = aws_iam_role.dms_cloudwatch_logs[0].name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonDMSCloudWatchLogsRole"
}

resource "aws_dms_replication_subnet_group" "this" {
  replication_subnet_group_id          = "${var.name}-dms"
  replication_subnet_group_description = "Subnets for the ${var.name} DMS replication"
  subnet_ids                           = var.subnet_ids

  tags = merge(local.tags, { Name = "${var.name}-dms" })

  # DMS needs dms-vpc-role before it will create a subnet group.
  depends_on = [aws_iam_role_policy_attachment.dms_vpc]
}

resource "aws_dms_certificate" "ca" {
  certificate_id  = "${var.name}-ca"
  certificate_pem = var.ca_certificate_pem

  tags = merge(local.tags, { Name = "${var.name}-ca" })
}

resource "aws_dms_endpoint" "source" {
  endpoint_id                     = "${var.name}-source"
  endpoint_type                   = "source"
  engine_name                     = "postgres"
  database_name                   = var.source_database_name
  ssl_mode                        = "verify-full"
  certificate_arn                 = aws_dms_certificate.ca.certificate_arn
  kms_key_arn                     = var.kms_key_arn
  secrets_manager_arn             = var.source_secret_arn
  secrets_manager_access_role_arn = aws_iam_role.secrets_access.arn

  tags = merge(local.tags, { Name = "${var.name}-source" })

  depends_on = [aws_iam_role_policy.secrets_access]
}

resource "aws_dms_endpoint" "target" {
  endpoint_id                     = "${var.name}-target"
  endpoint_type                   = "target"
  engine_name                     = "postgres"
  database_name                   = var.target_database_name
  ssl_mode                        = "verify-full"
  certificate_arn                 = aws_dms_certificate.ca.certificate_arn
  kms_key_arn                     = var.kms_key_arn
  secrets_manager_arn             = var.target_secret_arn
  secrets_manager_access_role_arn = aws_iam_role.secrets_access.arn

  tags = merge(local.tags, { Name = "${var.name}-target" })

  depends_on = [aws_iam_role_policy.secrets_access]
}

resource "aws_dms_replication_config" "this" {
  replication_config_identifier = var.name
  replication_type              = "full-load"
  source_endpoint_arn           = aws_dms_endpoint.source.endpoint_arn
  target_endpoint_arn           = aws_dms_endpoint.target.endpoint_arn
  table_mappings                = local.table_mappings
  replication_settings          = local.replication_settings
  start_replication             = false

  compute_config {
    replication_subnet_group_id = aws_dms_replication_subnet_group.this.replication_subnet_group_id
    vpc_security_group_ids      = [aws_security_group.this.id]
    min_capacity_units          = var.min_capacity_units
    max_capacity_units          = var.max_capacity_units
    multi_az                    = false
    kms_key_id                  = var.kms_key_arn
  }

  tags = merge(local.tags, { Name = var.name })

  depends_on = [aws_iam_role_policy_attachment.dms_cloudwatch_logs]

  lifecycle {
    ignore_changes = [start_replication]

    precondition {
      condition     = var.min_capacity_units <= var.max_capacity_units
      error_message = "min_capacity_units must not be greater than max_capacity_units."
    }
  }
}
