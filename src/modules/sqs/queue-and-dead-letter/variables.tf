variable "name" {
  description = "Nombre de la cola principal (<recurso>-<entorno>). La DLQ se llama <name>-dlq."
  type        = string
}

variable "visibility_timeout_seconds" {
  description = "Visibility timeout de la cola principal."
  type        = number
  default     = 30
}

variable "message_retention_seconds" {
  description = "Retención de mensajes en la cola principal. Null = default de SQS (4 días)."
  type        = number
  default     = null
}

variable "max_receive_count" {
  description = "Intentos antes de mover el mensaje a la DLQ."
  type        = number
  default     = 5
}

variable "tags" {
  description = "Tags obligatorios: Project, Environment, Owner, CostCenter."
  type        = map(string)
}
