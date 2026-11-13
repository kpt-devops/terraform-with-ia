variable "name" {
  description = "Nombre del topic (<recurso>-<entorno>)."
  type        = string
}

variable "publisher_services" {
  description = "Servicios de AWS autorizados a publicar, ej. [\"costalerts.amazonaws.com\"]."
  type        = list(string)
  default     = []
}

variable "subscriptions" {
  description = "Suscripciones: { clave = { protocol = \"lambda\", endpoint = \"<arn>\" } }."
  type = map(object({
    protocol = string
    endpoint = string
  }))
  default = {}
}

variable "kms_master_key_id" {
  description = "Clave KMS del topic. Null solo cuando un publicador no admite KMS (ej. Cost Anomaly Detection)."
  type        = string
  default     = null
}

variable "tags" {
  description = "Tags obligatorios: Project, Environment, Owner, CostCenter."
  type        = map(string)
}
