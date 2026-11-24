variable "name" {
  description = "Nombre de la función (<recurso>-<entorno>)."
  type        = string
}

variable "description" {
  description = "Qué hace la función."
  type        = string
  default     = ""
}

variable "source_path" {
  description = "Carpeta con el código, normalmente en src/apps/<nombre>."
  type        = string
}

variable "handler" {
  description = "Punto de entrada."
  type        = string
  default     = "handler.handler"
}

variable "runtime" {
  description = "Runtime de Lambda."
  type        = string
  default     = "python3.12"
}

variable "timeout" {
  description = "Timeout en segundos."
  type        = number
  default     = 30
}

variable "memory_size" {
  description = "Memoria en MB."
  type        = number
  default     = 256
}

variable "reserved_concurrent_executions" {
  description = "Concurrencia reservada. -1 = sin límite."
  type        = number
  default     = -1
}

variable "environment_variables" {
  description = "Variables de entorno. Nunca secretos: usa SSM o Secrets Manager."
  type        = map(string)
  default     = {}
}

variable "policy_json" {
  description = "Política IAM adicional (JSON) para el rol de la función. Null = solo logs y X-Ray."
  type        = string
  default     = null
}

variable "allowed_triggers" {
  description = "Quién puede invocar la función: { clave = { principal = \"sns.amazonaws.com\", source_arn = \"<arn>\" } }. Para una Function URL pública se usan action, function_url_auth_type e invoked_via_function_url."
  type = map(object({
    principal                = string
    source_arn               = optional(string)
    action                   = optional(string)
    function_url_auth_type   = optional(string)
    invoked_via_function_url = optional(bool)
  }))
  default = {}
}

variable "log_retention_days" {
  description = "Retención de los logs de la función."
  type        = number
  default     = 14
}

variable "tags" {
  description = "Tags obligatorios: Project, Environment, Owner, CostCenter."
  type        = map(string)
}

variable "log_format" {
  description = "Formato de logs: Text o JSON. JSON permite filtrar por campos en Logs Insights."
  type        = string
  default     = "Text"

  validation {
    condition     = contains(["Text", "JSON"], var.log_format)
    error_message = "log_format debe ser Text o JSON."
  }
}

variable "application_log_level" {
  description = "Nivel de logs de la aplicación (solo con log_format = JSON): TRACE, DEBUG, INFO, WARN, ERROR o FATAL."
  type        = string
  default     = "INFO"
}

variable "durable_execution_timeout" {
  description = "Activa Lambda durable functions: duración máxima de una ejecución en segundos (1 a 31622400). Null = función normal. Solo se puede activar al crear la función."
  type        = number
  default     = null
}

variable "durable_retention_days" {
  description = "Días que se conserva el estado de una ejecución durable terminada (1 a 90)."
  type        = number
  default     = 7
}

variable "publish" {
  description = "Publica una versión en cada cambio. Siempre true si la función es durable."
  type        = bool
  default     = false
}

variable "alias_name" {
  description = "Crea un alias que apunta a la última versión publicada. Requiere publish o durable."
  type        = string
  default     = null
}

variable "function_url_auth_type" {
  description = "Crea una Function URL: AWS_IAM o NONE (pública; la app debe validar su propio secreto). Null = sin URL."
  type        = string
  default     = null

  validation {
    condition     = var.function_url_auth_type == null || contains(["AWS_IAM", "NONE"], coalesce(var.function_url_auth_type, "AWS_IAM"))
    error_message = "function_url_auth_type debe ser AWS_IAM, NONE o null."
  }
}

variable "event_source_mapping" {
  description = "Event source mappings (por ejemplo, una cola SQS): mismo formato que terraform-aws-modules/lambda."
  type        = any
  default     = {}
}
