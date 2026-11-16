output "replication_task_arn" {
  description = "ARN of the DMS replication task. Use it to start the migration and check table statistics."
  value       = aws_dms_replication_task.this.replication_task_arn
}

output "security_group_id" {
  description = "ID of the security group attached to the DMS replication instance."
  value       = aws_security_group.this.id
}
