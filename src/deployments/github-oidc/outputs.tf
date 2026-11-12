output "plan_role_arn" {
  description = "Valor del secreto AWS_PLAN_ROLE_ARN en el GitHub Environment del mismo entorno."
  value       = module.plan_role.arn
}

output "oidc_provider_arn" {
  value = local.oidc_provider_arn
}
