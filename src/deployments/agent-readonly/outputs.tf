output "agent_role_arn" {
  description = "role_arn del perfil terraform-with-ia-agent en ~/.aws/config."
  value       = module.agent_role.arn
}
