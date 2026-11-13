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
