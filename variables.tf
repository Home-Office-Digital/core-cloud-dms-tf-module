variable "name" {
  description = "Name of the migration, used to prefix every resource, for example `systems-register-test`."
  type        = string
  nullable    = false

  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{1,40}[a-z0-9]$", var.name)) && !strcontains(var.name, "--") && !startswith(var.name, "sg-")
    error_message = "name must be 3-42 characters of lowercase letters, numbers and hyphens, starting with a letter, not ending with a hyphen, not containing consecutive hyphens and not starting with sg- (reserved by EC2 for security groups)."
  }
}

variable "tags" {
  description = "Core Cloud mandatory tags, applied to every resource."
  type = object({
    cost-centre      = string
    account-code     = string
    portfolio-id     = string
    project-id       = string
    service-id       = string
    environment-type = string
    owner-business   = string
    budget-holder    = string
    source-repo      = optional(string)
    hosting-platform = optional(string)
  })
  nullable = false
}

variable "kms_key_arn" {
  description = "ARN of a customer managed KMS key used to encrypt the endpoints and replication instance storage. DMS is also allowed to decrypt the endpoint secrets with it."
  type        = string
  nullable    = false

  validation {
    condition     = can(regex("^arn:aws:kms:[a-z0-9-]+:[0-9]{12}:key/", var.kms_key_arn))
    error_message = "kms_key_arn must be a KMS key ARN (arn:aws:kms:<region>:<account>:key/<id>)."
  }
}

variable "vpc_id" {
  description = "ID of the VPC that DMS runs in."
  type        = string
  nullable    = false
}

variable "subnet_ids" {
  description = "Private subnet IDs for DMS, in at least two Availability Zones. The source database must allow inbound 5432 from these subnets."
  type        = list(string)
  nullable    = false

  validation {
    condition     = length(var.subnet_ids) >= 2
    error_message = "subnet_ids must contain at least two subnets in different Availability Zones."
  }
}

variable "source_cidr_blocks" {
  description = "CIDR blocks of the source database. DMS is allowed outbound to these on 5432."
  type        = list(string)
  nullable    = false

  validation {
    condition     = length(var.source_cidr_blocks) > 0 && alltrue([for c in var.source_cidr_blocks : can(cidrnetmask(c)) && try(cidrnetmask(c), "") != "0.0.0.0"])
    error_message = "source_cidr_blocks must contain at least one valid IPv4 CIDR block and must not include a /0 network."
  }
}

variable "target_security_group_id" {
  description = "Security group of the target RDS instance. DMS is allowed outbound to it on 5432. The target must allow inbound 5432 from subnet_ids."
  type        = string
  nullable    = false
}

variable "aws_service_cidr_blocks" {
  description = "CIDR blocks of the VPC endpoints DMS uses for Secrets Manager and KMS. Defaults to the Core Cloud central VPC endpoints range."
  type        = list(string)
  default     = ["10.252.80.0/21"]
  nullable    = false

  validation {
    condition     = length(var.aws_service_cidr_blocks) > 0 && alltrue([for c in var.aws_service_cidr_blocks : can(cidrnetmask(c)) && try(cidrnetmask(c), "") != "0.0.0.0"])
    error_message = "aws_service_cidr_blocks must contain at least one valid IPv4 CIDR block and must not include a /0 network."
  }
}

variable "source_database_name" {
  description = "Name of the database to migrate from."
  type        = string
  nullable    = false
}

variable "target_database_name" {
  description = "Name of the database to migrate into. It must already exist on the target."
  type        = string
  nullable    = false
}

variable "source_secret_arn" {
  description = "ARN of the Secrets Manager secret with the source host, port, username and password."
  type        = string
  nullable    = false
}

variable "target_secret_arn" {
  description = "ARN of the Secrets Manager secret with the target host, port, username and password. RDS-managed master user secrets cannot be used because they do not include host and port."
  type        = string
  nullable    = false
}

variable "ca_certificate_pem" {
  description = "PEM bundle of the CA certificates that signed the source and target database certificates. Both endpoints use verify-full against it. For RDS, use the AWS global bundle (global-bundle.pem)."
  type        = string
  nullable    = false

  validation {
    condition     = strcontains(var.ca_certificate_pem, "-----BEGIN CERTIFICATE-----")
    error_message = "ca_certificate_pem must be a PEM-encoded certificate bundle."
  }
}

variable "include_schemas" {
  description = "Schemas to migrate. Every table in each schema is included. Names must not contain % or _, which DMS treats as wildcards."
  type        = list(string)
  nullable    = false

  validation {
    condition     = length(var.include_schemas) > 0
    error_message = "include_schemas must contain at least one schema."
  }

  validation {
    condition     = alltrue([for s in var.include_schemas : !strcontains(s, "%") && !strcontains(s, "_")])
    error_message = "include_schemas must not contain % or _. DMS treats them as wildcards and cannot escape them for PostgreSQL, so other schemas could be selected and truncated."
  }
}

variable "min_capacity_units" {
  description = "Minimum DMS capacity units (DCUs). 1 DCU is 2 GB of memory."
  type        = number
  default     = 1
  nullable    = false

  validation {
    condition     = contains([1, 2, 4, 8, 16, 32, 64, 128, 192, 256, 384], var.min_capacity_units)
    error_message = "min_capacity_units must be one of 1, 2, 4, 8, 16, 32, 64, 128, 192, 256 or 384."
  }
}

variable "max_capacity_units" {
  description = "Maximum DMS capacity units (DCUs). 1 DCU is 2 GB of memory."
  type        = number
  default     = 4
  nullable    = false

  validation {
    condition     = contains([1, 2, 4, 8, 16, 32, 64, 128, 192, 256, 384], var.max_capacity_units)
    error_message = "max_capacity_units must be one of 1, 2, 4, 8, 16, 32, 64, 128, 192, 256 or 384."
  }
}

variable "create_dms_service_roles" {
  description = "Whether to create dms-vpc-role and dms-cloudwatch-logs-role. AWS requires these exact names, so only one stack per account can own them. Set to false if they already exist in the account."
  type        = bool
  default     = true
  nullable    = false
}
