mock_provider "aws" {
  mock_data "aws_caller_identity" {
    defaults = {
      account_id = "111111111111"
    }
  }

  mock_data "aws_iam_policy_document" {
    defaults = {
      json = "{\"Version\":\"2012-10-17\",\"Statement\":[]}"
    }
  }
}

variables {
  name                     = "systems-register-test"
  kms_key_arn              = "arn:aws:kms:eu-west-2:111111111111:key/00000000-0000-0000-0000-000000000000"
  vpc_id                   = "vpc-00000000000000000"
  subnet_ids               = ["subnet-aaaaaaaaaaaaaaaaa", "subnet-bbbbbbbbbbbbbbbbb", "subnet-ccccccccccccccccc"]
  source_cidr_blocks       = ["10.250.24.0/21"]
  target_security_group_id = "sg-00000000000000000"
  source_database_name     = "systemregister"
  target_database_name     = "systemregister"
  source_secret_arn        = "arn:aws:secretsmanager:eu-west-2:111111111111:secret:dms-source-AbCdEf"
  target_secret_arn        = "arn:aws:secretsmanager:eu-west-2:111111111111:secret:dms-target-GhIjKl"
  ca_certificate_pem       = "-----BEGIN CERTIFICATE-----\nMIIBtest\n-----END CERTIFICATE-----\n"
  include_schemas          = ["eventstore", "public"]

  tags = {
    cost-centre      = "CC1001"
    account-code     = "AC2002"
    portfolio-id     = "CTO"
    project-id       = "CC"
    service-id       = "dms"
    environment-type = "notprod"
    owner-business   = "owner@example.com"
    budget-holder    = "budget@example.com"
  }
}

run "replication_is_a_full_load_that_does_not_start_on_apply" {
  command = plan

  assert {
    condition     = aws_dms_replication_config.this.replication_type == "full-load"
    error_message = "Expected a full-load replication."
  }

  assert {
    condition     = aws_dms_replication_config.this.start_replication == false
    error_message = "Expected the replication not to start on apply."
  }
}

run "endpoints_are_postgres_with_ssl_cmk_and_secrets" {
  command = plan

  assert {
    condition     = aws_dms_endpoint.source.engine_name == "postgres" && aws_dms_endpoint.target.engine_name == "postgres"
    error_message = "Expected postgres on both endpoints."
  }

  assert {
    condition     = aws_dms_endpoint.source.ssl_mode == "verify-full" && aws_dms_endpoint.target.ssl_mode == "verify-full"
    error_message = "Expected both endpoints to use verify-full."
  }

  assert {
    condition     = aws_dms_certificate.ca.certificate_pem == var.ca_certificate_pem
    error_message = "Expected the supplied CA bundle to be imported for the endpoints."
  }

  assert {
    condition     = aws_dms_endpoint.source.secrets_manager_arn == var.source_secret_arn && aws_dms_endpoint.target.secrets_manager_arn == var.target_secret_arn
    error_message = "Expected endpoints to read credentials from Secrets Manager."
  }
}

run "serverless_compute_is_sized" {
  command = plan

  assert {
    condition     = aws_dms_replication_config.this.compute_config[0].min_capacity_units == 1 && aws_dms_replication_config.this.compute_config[0].max_capacity_units == 4
    error_message = "Expected 1-4 DCUs by default."
  }
}

run "settings_protect_lob_data_and_validate" {
  command = plan

  assert {
    condition     = jsondecode(aws_dms_replication_config.this.replication_settings).TargetMetadata.FullLobMode == true
    error_message = "Expected full LOB mode so bytea values are not truncated."
  }

  assert {
    condition     = jsondecode(aws_dms_replication_config.this.replication_settings).FullLoadSettings.TargetTablePrepMode == "TRUNCATE_BEFORE_LOAD"
    error_message = "Expected truncate-before-load so a pre-created schema is kept."
  }

  assert {
    condition     = jsondecode(aws_dms_replication_config.this.replication_settings).ValidationSettings.EnableValidation == true
    error_message = "Expected data validation to be enabled."
  }
}

run "table_mappings_select_every_table_in_each_schema" {
  command = plan

  assert {
    condition     = length(jsondecode(aws_dms_replication_config.this.table_mappings).rules) == 2
    error_message = "Expected one selection rule per schema."
  }

  assert {
    condition     = jsondecode(aws_dms_replication_config.this.table_mappings).rules[0]["object-locator"]["schema-name"] == "eventstore"
    error_message = "Expected the first rule to select the eventstore schema."
  }

  assert {
    condition     = jsondecode(aws_dms_replication_config.this.table_mappings).rules[1]["object-locator"]["table-name"] == "%"
    error_message = "Expected every table in the schema to be included."
  }
}

run "egress_is_scoped_to_source_target_and_endpoints" {
  command = plan

  assert {
    condition     = length(aws_vpc_security_group_egress_rule.to_source) == 1 && aws_vpc_security_group_egress_rule.to_source["10.250.24.0/21"].from_port == 5432
    error_message = "Expected one egress rule to the source CIDR on 5432."
  }

  assert {
    condition     = aws_vpc_security_group_egress_rule.to_target.referenced_security_group_id == "sg-00000000000000000" && aws_vpc_security_group_egress_rule.to_target.from_port == 5432
    error_message = "Expected egress to the target security group on 5432."
  }

  assert {
    condition     = aws_vpc_security_group_egress_rule.to_aws_services["10.252.80.0/21"].from_port == 443
    error_message = "Expected HTTPS egress to the Core Cloud central VPC endpoints by default."
  }
}

run "secrets_policy_is_scoped" {
  command = plan

  assert {
    condition = toset(jsondecode(aws_iam_role_policy.secrets_access.policy).Statement[0].Resource) == toset([
      "arn:aws:secretsmanager:eu-west-2:111111111111:secret:dms-source-AbCdEf",
      "arn:aws:secretsmanager:eu-west-2:111111111111:secret:dms-target-GhIjKl",
    ])
    error_message = "Expected the policy to allow only the source and target secrets."
  }

  assert {
    condition     = jsondecode(aws_iam_role_policy.secrets_access.policy).Statement[1].Resource == [var.kms_key_arn]
    error_message = "Expected decrypt to be limited to the supplied CMK."
  }
}

run "dms_service_roles_created_by_default" {
  command = plan

  assert {
    condition     = aws_iam_role.dms_vpc[0].name == "dms-vpc-role" && aws_iam_role.dms_cloudwatch_logs[0].name == "dms-cloudwatch-logs-role"
    error_message = "Expected the account-level DMS roles with the exact names AWS requires."
  }
}

run "dms_service_roles_can_be_skipped" {
  command = plan

  variables {
    create_dms_service_roles = false
  }

  assert {
    condition     = length(aws_iam_role.dms_vpc) == 0 && length(aws_iam_role.dms_cloudwatch_logs) == 0
    error_message = "Expected no account-level DMS roles when create_dms_service_roles is false."
  }
}

run "tags_are_applied" {
  command = plan

  assert {
    condition     = aws_dms_replication_config.this.tags["service-id"] == "dms" && aws_iam_role.secrets_access.tags["cost-centre"] == "CC1001"
    error_message = "Expected Core Cloud tags on module resources."
  }

  assert {
    condition     = !contains(keys(aws_security_group.this.tags), "source-repo")
    error_message = "Expected optional tags that were not supplied to be left out."
  }
}

run "dms_roles_trust_only_this_account" {
  command = plan

  assert {
    condition = anytrue([
      for st in data.aws_iam_policy_document.dms_assume_role.statement :
      anytrue([for c in st.condition : c.variable == "aws:SourceAccount" && toset(c.values) == toset(["111111111111"])])
    ])
    error_message = "Expected the DMS trust policy to be limited to this account with aws:SourceAccount."
  }
}

run "permissions_boundary_is_set_on_every_role" {
  command = plan

  variables {
    permissions_boundary_arn = "arn:aws:iam::111111111111:policy/tenant-boundary"
  }

  assert {
    condition = alltrue([
      aws_iam_role.secrets_access.permissions_boundary == var.permissions_boundary_arn,
      aws_iam_role.dms_vpc[0].permissions_boundary == var.permissions_boundary_arn,
      aws_iam_role.dms_cloudwatch_logs[0].permissions_boundary == var.permissions_boundary_arn,
    ])
    error_message = "Expected the permissions boundary on all three roles."
  }
}

