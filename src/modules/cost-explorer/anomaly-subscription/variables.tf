variable "name" {
  description = "Nombre de la suscripción."
  type        = string
}

variable "monitor_arn_list" {
  description = "Monitores de CAD que alimentan la suscripción."
  type        = list(string)
}

variable "sns_topic_arn" {
  description = "Topic que recibe la alerta. Debe permitir publicar a costalerts.amazonaws.com."
  type        = string
}

variable "frequency" {
  description = "IMMEDIATE (requiere SNS), DAILY o WEEKLY."
  type        = string
  default     = "IMMEDIATE"
}

variable "impact_threshold_usd" {
  description = "Impacto mínimo (USD) para enviar la alerta."
  type        = number
}

variable "tags" {
  description = "Tags del recurso (de utils/tagger)."
  type        = map(string)
}
