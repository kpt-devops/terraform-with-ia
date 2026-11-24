output "name" {
  value = var.name
}

output "arn" {
  value = module.alarm.cloudwatch_metric_alarm_arn
}
