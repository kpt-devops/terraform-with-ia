# Identidad del agente local para el AWS MCP Server: ve la configuración de la infraestructura,
# no los datos ni los secretos, y no puede modificar nada.
# Se aplica a mano: scripts/tf.sh <entorno> agent-readonly apply
# Luego, en ~/.aws/config, un perfil terraform-with-ia-agent con role_arn = output agent_role_arn.

locals {
  environment = module.env.environment
  cfg         = module.env.config

  # Por defecto confía en la cuenta: solo pueden asumirlo los principals con permiso sts:AssumeRole sobre él.
  trusted_principal_arns = try(local.cfg.trusted_principal_arns, ["arn:aws:iam::${data.aws_caller_identity.current.account_id}:root"])
}

module "env" {
  source  = "../../utils/environment"
  project = "agent-readonly"
}

module "tagger" {
  source      = "../../utils/tagger"
  project     = "agent-readonly"
  cost_center = "platform"
}

data "aws_caller_identity" "current" {}

# ReadOnlyAccess incluye lecturas de datos. Para revisar infraestructura basta la configuración,
# así que se niegan explícitamente las lecturas de contenido y secretos.
data "aws_iam_policy_document" "deny_data" {
  statement {
    sid    = "DenyDataAndSecretReads"
    effect = "Deny"
    actions = [
      "s3:GetObject*",
      "secretsmanager:GetSecretValue",
      "secretsmanager:BatchGetSecretValue",
      "ssm:GetParameter*",
      "kms:Decrypt",
      "sqs:ReceiveMessage",
      "dynamodb:GetItem",
      "dynamodb:BatchGetItem",
      "dynamodb:Query",
      "dynamodb:Scan",
      "dynamodb:PartiQLSelect",
      "kinesis:GetRecords",
      "athena:GetQueryResults",
      "ecr:BatchGetImage",
      "ecr:GetDownloadUrlForLayer",
      "lambda:GetFunction",
      "ec2:GetPasswordData",
    ]
    # Los logs de CloudWatch quedan permitidos a propósito: el agente los usa para revisar.
    resources = ["*"]
  }
}

module "agent_role" {
  source = "../../modules/iam/assumable-role"

  name                   = "agent-readonly-${local.environment}"
  description            = "Agente local (AWS MCP Server): solo configuración, sin datos ni escritura"
  trusted_principal_arns = local.trusted_principal_arns
  require_mfa            = try(local.cfg.require_mfa, false)
  managed_policy_arns    = ["arn:aws:iam::aws:policy/ReadOnlyAccess"]
  inline_policy_json     = data.aws_iam_policy_document.deny_data.json
  tags                   = module.tagger.tags
}
