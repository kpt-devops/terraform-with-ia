output "environment" {
  value = local.environment
}

# nonsensitive: la config se usa en count/for_each. Secretos de verdad (tokens, passwords) no van aquí:
# la aplicación los lee en runtime desde SSM/Secrets Manager.
output "config" {
  description = "Config del deployment para el entorno activo (JSON decodificado)."
  value       = nonsensitive(jsondecode(data.aws_ssm_parameter.config.value))
}
