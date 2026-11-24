output "function_name" {
  value = module.function.lambda_function_name
}

output "function_arn" {
  value = module.function.lambda_function_arn
}

output "version" {
  description = "Última versión publicada (\"$LATEST\" si la función no publica versiones)."
  value       = module.function.lambda_function_version
}

output "alias_arn" {
  description = "ARN del alias (null si no se pidió alias_name)."
  value       = one(aws_lambda_alias.this[*].arn)
}

output "function_url" {
  description = "Function URL (null si no se pidió)."
  value       = module.function.lambda_function_url
}

output "role_arn" {
  value = module.function.lambda_role_arn
}

output "log_group_name" {
  value = module.function.lambda_cloudwatch_log_group_name
}
