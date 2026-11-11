output "orders_queue_url" {
  value = module.orders_queue.queue_url
}

output "cost_explainer_lambda_name" {
  value = try(module.cost_explainer[0].lambda_name, null)
}
