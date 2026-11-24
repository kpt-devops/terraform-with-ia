# Demo 2: una DLQ que pide permiso antes de reprocesar (guía: demos/dlq-approval).
#   DLQ -> CloudWatch alarm -> EventBridge -> starter -> Lambda durable -> Telegram
#   clic -> webhook (Function URL) -> callback -> Lambda durable -> redrive a la cola original
# Fase 1: aprobación + redrive completo. La cola y su consumidor vienen del deployment sqs-orders.

locals {
  name         = "dlq-approval-${module.env.environment}"
  cfg          = module.env.config
  queue_name   = try(local.cfg.queue_name, "orders-${module.env.environment}")
  workflow_fn  = "${local.name}-workflow"
  ssm_arn      = "arn:aws:ssm:${data.aws_region.current.region}:${data.aws_caller_identity.current.account_id}:parameter"
  workflow_arn = "arn:aws:lambda:${data.aws_region.current.region}:${data.aws_caller_identity.current.account_id}:function:${local.workflow_fn}"

  telegram_token_param   = try(local.cfg.telegram_token_param, "/dlq-approval/telegram-bot-token")
  webhook_secret_param   = try(local.cfg.webhook_secret_param, "/dlq-approval/telegram-webhook-secret")
  approval_timeout_hours = try(local.cfg.approval_timeout_hours, 24)
}

module "env" {
  source  = "../../utils/environment"
  project = "dlq-approval"
}

module "tagger" {
  source      = "../../utils/tagger"
  project     = "dlq-approval"
  cost_center = "demos"
}

data "aws_caller_identity" "current" {}
data "aws_region" "current" {}

data "aws_sqs_queue" "source" {
  name = local.queue_name
}

data "aws_sqs_queue" "dlq" {
  name = "${local.queue_name}-dlq"
}

# Referencias cortas de los botones de Telegram (callback_data admite 64 bytes; un callback id llega a 1024).
module "refs" {
  source = "../../modules/dynamodb/table"

  name          = "${local.name}-refs"
  hash_key      = "ref"
  ttl_attribute = "expires_at"
  tags          = module.tagger.tags
}

# Aviso con el primer mensaje visible en la DLQ. Sin acciones: el cambio de estado llega a EventBridge.
module "dlq_alarm" {
  source = "../../modules/cloudwatch/metric-alarm"

  name        = "${local.queue_name}-dlq-messages"
  description = "Hay mensajes en la DLQ de ${local.queue_name}: la Lambda durable pide aprobación para reprocesarlos."
  namespace   = "AWS/SQS"
  metric_name = "ApproximateNumberOfMessagesVisible"
  dimensions  = { QueueName = data.aws_sqs_queue.dlq.name }
  threshold   = 0
  tags        = module.tagger.tags
}

module "alarm_rule" {
  source = "../../modules/eventbridge/rule-to-lambda"

  name        = "${local.name}-dlq-alarm"
  description = "La alarma de la DLQ pasa a ALARM: inicia el flujo de aprobación."
  event_pattern = {
    source        = ["aws.cloudwatch"]
    "detail-type" = ["CloudWatch Alarm State Change"]
    resources     = [module.dlq_alarm.arn]
    detail        = { state = { value = ["ALARM"] } }
  }
  lambda_arn = module.starter.function_arn
  tags       = module.tagger.tags
}

# ---------- Función durable (flujo de aprobación y redrive) ----------

data "aws_iam_policy_document" "workflow" {
  statement {
    sid       = "InspectAndRedriveDlq"
    actions   = ["sqs:GetQueueAttributes", "sqs:StartMessageMoveTask", "sqs:ListMessageMoveTasks", "sqs:ReceiveMessage", "sqs:DeleteMessage"]
    resources = [data.aws_sqs_queue.dlq.arn]
  }

  statement {
    sid       = "RedriveDestination"
    actions   = ["sqs:SendMessage"]
    resources = [data.aws_sqs_queue.source.arn]
  }

  statement {
    sid       = "ButtonRefs"
    actions   = ["dynamodb:PutItem"]
    resources = [module.refs.arn]
  }

  statement {
    sid       = "TelegramToken"
    actions   = ["ssm:GetParameter"]
    resources = ["${local.ssm_arn}${local.telegram_token_param}"]
  }
}

module "workflow" {
  source = "../../modules/lambda/function"

  name               = local.workflow_fn
  description        = "Durable: revisa la DLQ, pide aprobación por Telegram y reprocesa si alguien aprueba"
  source_path        = "${path.module}/../../apps/dlq-approval"
  handler            = "workflow.handler"
  runtime            = "python3.14"
  timeout            = 60 # por invocación; la ejecución completa la limita durable_execution_timeout
  attach_policy_json = true
  policy_json        = data.aws_iam_policy_document.workflow.json

  durable_execution_timeout = (local.approval_timeout_hours + 2) * 3600
  durable_retention_days    = 7
  alias_name                = "live"

  environment_variables = {
    DLQ_URL                = data.aws_sqs_queue.dlq.url
    DLQ_ARN                = data.aws_sqs_queue.dlq.arn
    QUEUE_NAME             = local.queue_name
    REFS_TABLE             = module.refs.name
    TELEGRAM_CHAT_ID       = local.cfg.telegram_chat_id
    TELEGRAM_TOKEN_PARAM   = local.telegram_token_param
    APPROVAL_TIMEOUT_HOURS = tostring(local.approval_timeout_hours)
  }

  tags = module.tagger.tags
}

# ---------- Starter (EventBridge -> durable con nombre de ejecución) ----------

data "aws_iam_policy_document" "starter" {
  statement {
    sid       = "StartDurableExecution"
    actions   = ["lambda:InvokeFunction"]
    resources = [module.workflow.alias_arn]
  }
}

module "starter" {
  source = "../../modules/lambda/function"

  name               = "${local.name}-starter"
  description        = "Inicia la ejecución durable con un nombre idempotente"
  source_path        = "${path.module}/../../apps/dlq-approval"
  handler            = "starter.handler"
  runtime            = "python3.14"
  timeout            = 10
  attach_policy_json = true
  policy_json        = data.aws_iam_policy_document.starter.json

  environment_variables = {
    DURABLE_FUNCTION_ARN = module.workflow.alias_arn
    QUEUE_NAME           = local.queue_name
  }

  allowed_triggers = {
    eventbridge = {
      principal  = "events.amazonaws.com"
      source_arn = module.alarm_rule.arn
    }
  }

  tags = module.tagger.tags
}

# ---------- Webhook de Telegram (Function URL pública con secret token) ----------

data "aws_iam_policy_document" "webhook" {
  statement {
    sid       = "TelegramSecrets"
    actions   = ["ssm:GetParameter"]
    resources = ["${local.ssm_arn}${local.telegram_token_param}", "${local.ssm_arn}${local.webhook_secret_param}"]
  }

  statement {
    sid       = "ConsumeButtonRef"
    actions   = ["dynamodb:DeleteItem"]
    resources = [module.refs.arn]
  }

  statement {
    sid       = "CompleteCallback"
    actions   = ["lambda:SendDurableExecutionCallbackSuccess", "lambda:SendDurableExecutionCallbackFailure"]
    resources = ["${local.workflow_arn}:*"]
  }
}

module "webhook" {
  source = "../../modules/lambda/function"

  name               = "${local.name}-webhook"
  description        = "Recibe el clic de Telegram y completa el callback de la ejecución durable"
  source_path        = "${path.module}/../../apps/dlq-approval"
  handler            = "webhook.handler"
  runtime            = "python3.14"
  timeout            = 15
  attach_policy_json = true
  policy_json        = data.aws_iam_policy_document.webhook.json

  function_url_auth_type = "NONE"

  environment_variables = {
    REFS_TABLE           = module.refs.name
    TELEGRAM_CHAT_ID     = local.cfg.telegram_chat_id
    TELEGRAM_TOKEN_PARAM = local.telegram_token_param
    WEBHOOK_SECRET_PARAM = local.webhook_secret_param
  }

  # Una Function URL pública necesita los dos permisos (InvokeFunctionUrl e InvokeFunction vía URL).
  allowed_triggers = {
    url = {
      principal              = "*"
      action                 = "lambda:InvokeFunctionUrl"
      function_url_auth_type = "NONE"
    }
    url_invoke = {
      principal                = "*"
      action                   = "lambda:InvokeFunction"
      invoked_via_function_url = true
    }
  }

  tags = module.tagger.tags
}
