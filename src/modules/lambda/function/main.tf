# Wrapper propio de Lambda. Implementación: terraform-aws-modules/lambda (aprobado en src/modules/catalog.md).
# Impone: X-Ray activo, retención de logs, empaquetado desde src/apps/ y tags.
# Opcional: durable functions (con versión publicada y alias), Function URL, event source mapping y logs JSON.

data "aws_region" "current" {}
data "aws_caller_identity" "current" {}

locals {
  durable = var.durable_execution_timeout != null

  # Checkpoints de una ejecución durable: ARN de la función con cualquier calificador (versión o alias).
  durable_execution_arn = "arn:aws:lambda:${data.aws_region.current.region}:${data.aws_caller_identity.current.account_id}:function:${var.name}:*"
}

module "function" {
  # checkov:skip=CKV_TF_1: módulo del Terraform Registry fijado por versión según src/modules/catalog.md.
  # checkov:skip=CKV_AWS_117: no se fuerza VPC; una función que necesite red privada debe extender este wrapper.
  # checkov:skip=CKV_AWS_173: regla del repo: las variables de entorno no llevan secretos (van en SSM/Secrets Manager).
  # checkov:skip=CKV_AWS_272: firma de código fuera del alcance de este repo de referencia.
  # checkov:skip=CKV_AWS_116: los reintentos los define el origen del evento; agregar DLQ cuando la función lo requiera.
  # checkov:skip=CKV_AWS_158: los logs no contienen secretos; cifrado por defecto de CloudWatch Logs.
  # checkov:skip=CKV_AWS_338: la retención se define por función con log_retention_days.
  # checkov:skip=CKV_AWS_50: X-Ray sí está activo (tracing_mode = "Active"); checkov no evalúa el bloque dynamic del módulo.
  # checkov:skip=CKV_AWS_258: la Function URL pública (NONE) solo existe si el deployment la pide; la app valida su propio secreto.
  # checkov:skip=CKV_AWS_301: el permiso público (principal "*") solo se crea para esa Function URL; la app valida su propio secreto.
  source  = "terraform-aws-modules/lambda/aws"
  version = "~> 8.12"

  function_name = var.name
  description   = var.description
  handler       = var.handler
  runtime       = var.runtime
  source_path   = var.source_path
  hash_extra    = var.name # varias funciones con el mismo source_path: un zip por función, sin carrera al empaquetar
  timeout       = var.timeout
  memory_size   = var.memory_size

  reserved_concurrent_executions = var.reserved_concurrent_executions
  environment_variables          = var.environment_variables

  attach_policy_json = var.attach_policy_json
  policy_json        = var.policy_json

  # Durable functions: se invocan con ARN calificado, así que publican versión.
  publish                          = var.publish || local.durable
  durable_config_execution_timeout = var.durable_execution_timeout
  durable_config_retention_period  = local.durable ? var.durable_retention_days : null

  attach_policy_statements = local.durable
  policy_statements = local.durable ? {
    durable_execution = {
      effect    = "Allow"
      actions   = ["lambda:CheckpointDurableExecution", "lambda:GetDurableExecutionState"]
      resources = [local.durable_execution_arn]
    }
  } : {}

  tracing_mode          = "Active"
  attach_tracing_policy = true

  cloudwatch_logs_retention_in_days = var.log_retention_days
  logging_log_format                = local.durable ? "JSON" : var.log_format # AWS exige JSON en durable functions
  logging_application_log_level     = var.application_log_level

  # Sin Function URL salvo que el deployment la pida; AWS_IAM por defecto.
  create_lambda_function_url = var.function_url_auth_type != null
  authorization_type         = coalesce(var.function_url_auth_type, "AWS_IAM")

  event_source_mapping = var.event_source_mapping

  allowed_triggers                        = var.allowed_triggers
  create_current_version_allowed_triggers = false # los permisos van sobre la función sin calificar

  tags = var.tags
}

# Alias estable para invocar siempre una versión publicada (obligatorio en durable functions).
resource "aws_lambda_alias" "this" {
  count = var.alias_name == null ? 0 : 1

  name             = var.alias_name
  function_name    = module.function.lambda_function_name
  function_version = module.function.lambda_function_version
}
