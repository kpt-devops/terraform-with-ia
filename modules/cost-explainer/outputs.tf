output "lambda_name" {
  value = aws_lambda_function.explainer.function_name
}

output "sns_topic_arn" {
  value = aws_sns_topic.anomalies.arn
}

output "monitor_arn" {
  value = local.monitor_arn
}
