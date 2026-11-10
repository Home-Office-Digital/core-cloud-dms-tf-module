locals {
  port = 5432

  # Drop optional tags that were not set.
  tags = { for k, v in var.tags : k => v if v != null }

  # One rule per schema, selecting every table.
  table_mappings = jsonencode({
    rules = [
      for i, schema in var.include_schemas : {
        rule-type      = "selection"
        rule-id        = tostring(i + 1)
        rule-name      = "include-${schema}"
        rule-action    = "include"
        object-locator = { schema-name = schema, table-name = "%" }
      }
    ]
  })

  # Full LOB mode so bytea/text is never truncated; truncate-before-load keeps a pre-created schema.
  replication_settings = jsonencode({
    TargetMetadata = {
      SupportLobs        = true
      FullLobMode        = true
      LobChunkSize       = 64
      LimitedSizeLobMode = false
    }
    FullLoadSettings   = { TargetTablePrepMode = "TRUNCATE_BEFORE_LOAD" }
    Logging            = { EnableLogging = true }
    ValidationSettings = { EnableValidation = true }
  })
}
