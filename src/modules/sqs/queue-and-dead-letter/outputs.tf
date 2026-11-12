output "queue_name" {
  value = module.queue.queue_name
}

output "queue_arn" {
  value = module.queue.queue_arn
}

output "queue_url" {
  value = module.queue.queue_url
}

output "dlq_name" {
  value = module.queue.dead_letter_queue_name
}

output "dlq_arn" {
  value = module.queue.dead_letter_queue_arn
}
