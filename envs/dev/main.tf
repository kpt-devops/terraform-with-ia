locals {
  environment = "dev"
  tags = {
    Project     = var.project
    Environment = local.environment
    Owner       = var.owner
    CostCenter  = "demos"
  }
}

# Ejemplo de referencia: el agente debe seguir este patrón.
module "orders_queue" {
  source = "../../modules/sqs-with-dlq"

  name = "${var.project}-${local.environment}-orders"
  tags = local.tags
}

# Agente que explica anomalías de Cost Anomaly Detection y las envía a Telegram.
# Guía de la demo: ../../demos/cost-explainer/README.md
module "cost_explainer" {
  source = "../../modules/cost-explainer"
  count  = var.enable_cost_explainer ? 1 : 0

  name                 = "${var.project}-${local.environment}-cost-explainer"
  telegram_chat_id     = var.telegram_chat_id
  existing_monitor_arn = var.cost_anomaly_monitor_arn
  bedrock_model_id     = var.bedrock_model_id
  cost_tag_key         = "Project"
  tags                 = local.tags
}
