data "aws_caller_identity" "current" {}
data "aws_region" "current" {}

locals {
  monitor_arn = var.existing_monitor_arn != "" ? var.existing_monitor_arn : aws_ce_anomaly_monitor.services[0].arn
}

# --- Alertas de Cost Anomaly Detection -> SNS ---

resource "aws_sns_topic" "anomalies" {
  # checkov:skip=CKV_AWS_26: CAD (costalerts.amazonaws.com) no puede publicar en un topic cifrado con la clave administrada aws/sns; el mensaje solo contiene metadatos de costo.
  name = "${var.name}-anomalies"
  tags = var.tags
}

resource "aws_sns_topic_policy" "anomalies" {
  arn = aws_sns_topic.anomalies.arn
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Sid       = "AllowCostAnomalyDetection"
      Effect    = "Allow"
      Principal = { Service = "costalerts.amazonaws.com" }
      Action    = "SNS:Publish"
      Resource  = aws_sns_topic.anomalies.arn
    }]
  })
}

resource "aws_ce_anomaly_monitor" "services" {
  count             = var.existing_monitor_arn == "" ? 1 : 0
  name              = "${var.name}-services"
  monitor_type      = "DIMENSIONAL"
  monitor_dimension = "SERVICE"
  tags              = var.tags
}

resource "aws_ce_anomaly_subscription" "immediate" {
  name             = "${var.name}-immediate"
  frequency        = "IMMEDIATE"
  monitor_arn_list = [local.monitor_arn]
  tags             = var.tags

  subscriber {
    type    = "SNS"
    address = aws_sns_topic.anomalies.arn
  }

  threshold_expression {
    dimension {
      key           = "ANOMALY_TOTAL_IMPACT_ABSOLUTE"
      match_options = ["GREATER_THAN_OR_EQUAL"]
      values        = [tostring(var.impact_threshold_usd)]
    }
  }

  depends_on = [aws_sns_topic_policy.anomalies]
}

# --- Lambda cost-explainer ---

data "archive_file" "lambda" {
  type        = "zip"
  source_dir  = "${path.module}/lambda"
  output_path = "${path.root}/.build/${var.name}.zip"
  excludes    = ["__pycache__"]
}

resource "aws_cloudwatch_log_group" "lambda" {
  # checkov:skip=CKV_AWS_158: los logs no contienen datos sensibles; se usa el cifrado por defecto de CloudWatch Logs.
  # checkov:skip=CKV_AWS_338: demo de bajo volumen; la retención se controla con log_retention_days.
  name              = "/aws/lambda/${var.name}"
  retention_in_days = var.log_retention_days
  tags              = var.tags
}

resource "aws_iam_role" "lambda" {
  name = "${var.name}-lambda"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "lambda.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })
  tags = var.tags
}

# Solo lectura: el agente explica, nunca modifica recursos.
data "aws_iam_policy_document" "lambda" {
  # checkov:skip=CKV_AWS_356: ce:GetCostAndUsage, cloudtrail:LookupEvents y xray:Put* no admiten acotar por recurso; todas las acciones son de lectura o telemetría.
  statement {
    sid       = "Logs"
    actions   = ["logs:CreateLogStream", "logs:PutLogEvents"]
    resources = ["${aws_cloudwatch_log_group.lambda.arn}:*"]
  }

  statement {
    sid       = "XRay"
    actions   = ["xray:PutTraceSegments", "xray:PutTelemetryRecords"]
    resources = ["*"]
  }

  statement {
    # Cost Explorer y CloudTrail LookupEvents no admiten permisos a nivel de recurso.
    sid       = "ReadCostAndTrail"
    actions   = ["ce:GetCostAndUsage", "ce:GetAnomalies", "cloudtrail:LookupEvents"]
    resources = ["*"]
  }

  statement {
    sid       = "TelegramToken"
    actions   = ["ssm:GetParameter"]
    resources = ["arn:aws:ssm:${data.aws_region.current.region}:${data.aws_caller_identity.current.account_id}:parameter${var.telegram_token_param}"]
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

resource "aws_iam_role_policy" "lambda" {
  name   = "${var.name}-read-only"
  role   = aws_iam_role.lambda.id
  policy = data.aws_iam_policy_document.lambda.json
}

resource "aws_lambda_function" "explainer" {
  # checkov:skip=CKV_AWS_116: la Lambda se invoca desde SNS; los reintentos y errores quedan en logs. Una DLQ no aporta en una demo de alertas.
  # checkov:skip=CKV_AWS_117: necesita salida a Internet (api.telegram.org); fuera de VPC evita un NAT Gateway.
  # checkov:skip=CKV_AWS_173: las variables de entorno no contienen secretos; el token vive en SSM SecureString.
  # checkov:skip=CKV_AWS_272: firma de código fuera del alcance de la demo.
  function_name                  = var.name
  role                           = aws_iam_role.lambda.arn
  runtime                        = "python3.12"
  handler                        = "handler.handler"
  filename                       = data.archive_file.lambda.output_path
  source_code_hash               = data.archive_file.lambda.output_base64sha256
  timeout                        = 60
  memory_size                    = 256
  reserved_concurrent_executions = 2

  tracing_config {
    mode = "Active"
  }

  environment {
    variables = {
      BEDROCK_MODEL_ID         = var.bedrock_model_id
      COST_TAG_KEY             = var.cost_tag_key
      TELEGRAM_CHAT_ID         = var.telegram_chat_id
      TELEGRAM_TOKEN_PARAM     = var.telegram_token_param
      MODEL_PRICE_IN_PER_MTOK  = tostring(var.model_price_in_per_mtok)
      MODEL_PRICE_OUT_PER_MTOK = tostring(var.model_price_out_per_mtok)
    }
  }

  tags       = var.tags
  depends_on = [aws_cloudwatch_log_group.lambda]
}

resource "aws_lambda_permission" "sns" {
  statement_id  = "AllowSNSInvoke"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.explainer.function_name
  principal     = "sns.amazonaws.com"
  source_arn    = aws_sns_topic.anomalies.arn
}

resource "aws_sns_topic_subscription" "lambda" {
  topic_arn = aws_sns_topic.anomalies.arn
  protocol  = "lambda"
  endpoint  = aws_lambda_function.explainer.arn
}
