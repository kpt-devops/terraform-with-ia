output "queue_arn" {
  value = module.sqs.queue_arn
}

output "queue_url" {
  value = module.sqs.queue_url
}

output "dlq_arn" {
  value = module.sqs.dlq_arn
}

output "consumer_function_name" {
  value = module.consumer.function_name
}
