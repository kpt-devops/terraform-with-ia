variable "name" {
  description = "Nombre de la cola principal (<proyecto>-<entorno>-<recurso>)."
  type        = string
}

variable "visibility_timeout_seconds" {
  description = "Visibility timeout de la cola principal."
  type        = number
  default     = 30
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
