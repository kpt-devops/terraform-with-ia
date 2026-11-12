# Agente que explica anomalías de costo y las envía a Telegram (guía: demos/cost-explainer).
#   Cost Anomaly Detection -> SNS -> Lambda (src/apps/cost-explainer) -> Telegram
# CAD es por cuenta: despliega este deployment en un solo entorno por cuenta AWS.

locals {
  name                 = "cost-explainer-${module.env.environment}"
  cfg                  = module.env.config
  existing_monitor_arn = try(local.cfg.existing_monitor_arn, "")
  telegram_token_param = try(local.cfg.telegram_token_param, "/cost-explainer/telegram-bot-token")
}

module "env" {
  source  = "../../utils/environment"
  project = "finops-cost-explainer"
}

module "tagger" {
  source      = "../../utils/tagger"
  project     = "finops-cost-explainer"
  cost_center = "finops"
}

data "aws_caller_identity" "current" {}
data "aws_region" "current" {}

module "sns" {
  source = "../../modules/sns/topic"

  name               = "${local.name}-anomalies"
  publisher_services = ["costalerts.amazonaws.com"]
  kms_master_key_id  = null # CAD no puede publicar en un topic cifrado con KMS
  subscriptions = {
    explainer = {
      protocol = "lambda"
      endpoint = module.lambda.function_arn
    }
  }
  tags = module.tagger.tags
}

module "anomaly_monitor" {
  source = "../../modules/cost-explorer/anomaly-monitor"
  count  = local.existing_monitor_arn == "" ? 1 : 0

  name = "${local.name}-services"
  tags = module.tagger.tags
}

module "anomaly_subscription" {
  source = "../../modules/cost-explorer/anomaly-subscription"

  name                 = "${local.name}-immediate"
  monitor_arn_list     = [local.existing_monitor_arn != "" ? local.existing_monitor_arn : module.anomaly_monitor[0].arn]
  sns_topic_arn        = module.sns.topic_arn
  impact_threshold_usd = try(local.cfg.impact_threshold_usd, 10)
  tags                 = module.tagger.tags
}

# Solo lectura: el agente explica, nunca modifica recursos.
data "aws_iam_policy_document" "lambda" {
  # checkov:skip=CKV_AWS_356: ce:GetCostAndUsage y cloudtrail:LookupEvents no admiten acotar por recurso; todas son acciones de lectura.
  statement {
    sid       = "ReadCostAndTrail"
    actions   = ["ce:GetCostAndUsage", "ce:GetAnomalies", "cloudtrail:LookupEvents"]
    resources = ["*"]
  }

  statement {
    sid       = "TelegramToken"
    actions   = ["ssm:GetParameter"]
    resources = ["arn:aws:ssm:${data.aws_region.current.region}:${data.aws_caller_identity.current.account_id}:parameter${local.telegram_token_param}"]
  }

  statement {
    sid     = "Bedrock"
    actions = ["bedrock:InvokeModel"]
    resources = [
      "arn:aws:bedrock:*::foundation-model/*",
      "arn:aws:bedrock:*:${data.aws_caller_identity.current.account_id}:inference-profile/*",
    ]
  }
}

module "lambda" {
  source = "../../modules/lambda/function"

  name                           = local.name
  description                    = "Explica anomalías de Cost Anomaly Detection y las envía a Telegram"
  source_path                    = "${path.module}/../../apps/cost-explainer"
  timeout                        = 60
  reserved_concurrent_executions = 2 # CloudTrail LookupEvents admite 2 TPS por cuenta y región
  policy_json                    = data.aws_iam_policy_document.lambda.json

  environment_variables = {
    BEDROCK_MODEL_ID         = try(local.cfg.bedrock_model_id, "")
    COST_TAG_KEY             = "Project"
    TELEGRAM_CHAT_ID         = local.cfg.telegram_chat_id
    TELEGRAM_TOKEN_PARAM     = local.telegram_token_param
    MODEL_PRICE_IN_PER_MTOK  = "1"
    MODEL_PRICE_OUT_PER_MTOK = "5"
  }

  allowed_triggers = {
    sns = {
      principal  = "sns.amazonaws.com"
      source_arn = module.sns.topic_arn
    }
  }

  tags = module.tagger.tags
}
