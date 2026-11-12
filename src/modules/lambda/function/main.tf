# Wrapper propio de Lambda. Implementación: terraform-aws-modules/lambda (aprobado en src/modules/catalog.md).
# Impone: X-Ray activo, retención de logs, empaquetado desde src/apps/ y tags.
module "function" {
  # checkov:skip=CKV_TF_1: módulo del Terraform Registry fijado por versión según src/modules/catalog.md.
  # checkov:skip=CKV_AWS_117: no se fuerza VPC; una función que necesite red privada debe extender este wrapper.
  # checkov:skip=CKV_AWS_173: regla del repo: las variables de entorno no llevan secretos (van en SSM/Secrets Manager).
  # checkov:skip=CKV_AWS_272: firma de código fuera del alcance de este repo de referencia.
  # checkov:skip=CKV_AWS_116: los reintentos los define el origen del evento; agregar DLQ cuando la función lo requiera.
  # checkov:skip=CKV_AWS_158: los logs no contienen secretos; cifrado por defecto de CloudWatch Logs.
  # checkov:skip=CKV_AWS_338: la retención se define por función con log_retention_days.
  source  = "terraform-aws-modules/lambda/aws"
  version = "~> 8.12"

  function_name = var.name
  description   = var.description
  handler       = var.handler
  runtime       = var.runtime
  source_path   = var.source_path
  timeout       = var.timeout
  memory_size   = var.memory_size

  reserved_concurrent_executions = var.reserved_concurrent_executions
  environment_variables          = var.environment_variables

  attach_policy_json = var.policy_json != null
  policy_json        = var.policy_json

  tracing_mode          = "Active"
  attach_tracing_policy = true

  cloudwatch_logs_retention_in_days = var.log_retention_days

  allowed_triggers                        = var.allowed_triggers
  create_current_version_allowed_triggers = false # sin versiones publicadas

  tags = var.tags
}
