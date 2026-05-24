output "database_name" {
  value = aws_glue_catalog_database.this.name
}

output "table_name" {
  value = aws_glue_catalog_table.telemetry.name
}