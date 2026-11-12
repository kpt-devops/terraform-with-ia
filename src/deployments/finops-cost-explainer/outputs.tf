output "lambda_name" {
  value = module.lambda.function_name
}

output "sns_topic_arn" {
  value = module.sns.topic_arn
}

output "monitor_arn" {
  value = module.anomaly_subscription.arn
}
