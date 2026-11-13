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
  description = "Quién puede invocar la función: { clave = { principal = \"sns.amazonaws.com\", source_arn = \"<arn>\" } }."
  type = map(object({
    principal  = string
    source_arn = string
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
