variable "name" {
  description = "Nombre de la regla."
  type        = string
}

variable "description" {
  description = "Qué eventos captura la regla."
  type        = string
}

variable "event_pattern" {
  description = "Patrón de eventos (objeto; se serializa a JSON)."
  type        = any
}

variable "lambda_arn" {
  description = "ARN de la función destino (sin calificar o con alias)."
  type        = string
}

variable "enabled" {
  description = "Estado de la regla."
  type        = bool
  default     = true
}

variable "max_event_age_seconds" {
  description = "Edad máxima de un evento antes de descartarlo."
  type        = number
  default     = 3600
}

variable "max_retry_attempts" {
  description = "Reintentos de EventBridge si la invocación falla."
  type        = number
  default     = 3
}

variable "tags" {
  description = "Tags obligatorios: Project, Environment, Owner, CostCenter."
  type        = map(string)
}
