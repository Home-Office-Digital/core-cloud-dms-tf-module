mock_provider "aws" {
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
  subnet_ids               = ["subnet-aaaaaaaaaaaaaaaaa", "subnet-bbbbbbbbbbbbbbbbb"]
  source_cidr_blocks       = ["10.250.24.0/21"]
  target_security_group_id = "sg-00000000000000000"
  source_database_name     = "systemregister"
  target_database_name     = "systemregister"
  source_secret_arn        = "arn:aws:secretsmanager:eu-west-2:111111111111:secret:dms-source-AbCdEf"
  target_secret_arn        = "arn:aws:secretsmanager:eu-west-2:111111111111:secret:dms-target-GhIjKl"
  include_schemas          = ["eventstore"]

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

run "rejects_invalid_name" {
  command = plan

  variables {
    name = "Systems_Register"
  }

  expect_failures = [var.name]
}

run "rejects_non_kms_arn" {
  command = plan

  variables {
    kms_key_arn = "alias/aws/dms"
  }

  expect_failures = [var.kms_key_arn]
}

run "rejects_single_subnet" {
  command = plan

  variables {
    subnet_ids = ["subnet-aaaaaaaaaaaaaaaaa"]
  }

  expect_failures = [var.subnet_ids]
}

run "rejects_open_source_cidr" {
  command = plan

  variables {
    source_cidr_blocks = ["0.0.0.0/0"]
  }

  expect_failures = [var.source_cidr_blocks]
}

run "rejects_open_aws_service_cidr" {
  command = plan

  variables {
    aws_service_cidr_blocks = ["0.0.0.0/0"]
  }

  expect_failures = [var.aws_service_cidr_blocks]
}

run "requires_a_schema" {
  command = plan

  variables {
    include_schemas = []
  }

  expect_failures = [var.include_schemas]
}

run "rejects_invalid_capacity" {
  command = plan

  variables {
    max_capacity_units = 3
  }

  expect_failures = [var.max_capacity_units]
}

run "requires_min_capacity_not_above_max" {
  command = plan

  variables {
    min_capacity_units = 8
    max_capacity_units = 4
  }

  expect_failures = [aws_dms_replication_config.this]
}

run "rejects_wildcard_characters_in_schema_names" {
  command = plan

  variables {
    include_schemas = ["app_core"]
  }

  expect_failures = [var.include_schemas]
}
