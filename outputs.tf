output "replication_config_arn" {
  description = "ARN of the DMS serverless replication. Use it to start the migration and check table statistics."
  value       = aws_dms_replication_config.this.arn
}

output "security_group_id" {
  description = "ID of the security group attached to the DMS replication."
  value       = aws_security_group.this.id
}
