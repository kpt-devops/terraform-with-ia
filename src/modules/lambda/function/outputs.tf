output "function_name" {
  value = module.function.lambda_function_name
}

output "function_arn" {
  value = module.function.lambda_function_arn
}

output "role_arn" {
  value = module.function.lambda_role_arn
}

output "log_group_name" {
  value = module.function.lambda_cloudwatch_log_group_name
}
