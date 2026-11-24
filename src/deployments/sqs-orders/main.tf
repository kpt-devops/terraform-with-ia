locals {
  name = "orders-${module.env.environment}"
}

module "env" {
  source  = "../../utils/environment"
  project = "sqs-orders"
}

module "tagger" {
  source      = "../../utils/tagger"
  project     = "sqs-orders"
  cost_center = "demos"
}

module "sqs" {
  source = "../../modules/sqs/queue-and-dead-letter"

  name                       = local.name
  visibility_timeout_seconds = try(module.env.config.visibility_timeout_seconds, 30)
  max_receive_count          = try(module.env.config.max_receive_count, 5)
  tags                       = module.tagger.tags
}

# Consumidor de la cola (demo 2). Fallos por mensaje + logs JSON con el messageId de cada error.
data "aws_iam_policy_document" "consumer" {
  statement {
    sid       = "ConsumeOrders"
    actions   = ["sqs:ReceiveMessage", "sqs:DeleteMessage", "sqs:GetQueueAttributes", "sqs:ChangeMessageVisibility"]
    resources = [module.sqs.queue_arn]
  }
}

module "consumer" {
  source = "../../modules/lambda/function"

  name               = "${local.name}-consumer"
  description        = "Procesa pedidos de la cola; reporta fallos por mensaje"
  source_path        = "${path.module}/../../apps/orders-consumer"
  runtime            = "python3.13"
  timeout            = 10 # menor que el visibility timeout de la cola
  attach_policy_json = true
  policy_json        = data.aws_iam_policy_document.consumer.json

  log_format            = "JSON"
  application_log_level = try(module.env.config.consumer_log_level, "ERROR")

  environment_variables = {
    SIMULATE_BUG = tostring(try(module.env.config.consumer_simulate_bug, false))
  }

  event_source_mapping = {
    orders = {
      event_source_arn        = module.sqs.queue_arn
      batch_size              = 10
      function_response_types = ["ReportBatchItemFailures"]
      enabled                 = try(module.env.config.consumer_enabled, true)
    }
  }

  tags = module.tagger.tags
}
