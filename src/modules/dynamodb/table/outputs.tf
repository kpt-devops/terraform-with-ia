output "name" {
  value = module.table.dynamodb_table_id
}

output "arn" {
  value = module.table.dynamodb_table_arn
}
