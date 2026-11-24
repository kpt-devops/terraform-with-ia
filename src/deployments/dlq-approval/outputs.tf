output "webhook_url" {
  description = "URL para registrar en Telegram con setWebhook (ver demos/dlq-approval)."
  value       = module.webhook.function_url
}

output "workflow_alias_arn" {
  value = module.workflow.alias_arn
}

output "dlq_alarm_name" {
  value = module.dlq_alarm.name
}

output "refs_table" {
  value = module.refs.name
}
