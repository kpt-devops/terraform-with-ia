variable "name" {
  description = "Nombre base de los recursos (<proyecto>-<entorno>-cost-explainer)."
  type        = string
}

variable "existing_monitor_arn" {
  description = "ARN de un monitor de CAD existente. Vacío = se crea un monitor por servicio (solo se permite uno por cuenta)."
  type        = string
  default     = ""
}

variable "impact_threshold_usd" {
  description = "Impacto mínimo (USD) para que CAD envíe la alerta inmediata."
  type        = number
  default     = 10
}

variable "telegram_chat_id" {
  description = "Chat ID de Telegram que recibe los análisis."
  type        = string
}

variable "telegram_token_param" {
  description = "Parámetro SSM (SecureString) con el token del bot. Se crea fuera de Terraform."
  type        = string
  default     = "/cost-explainer/telegram-bot-token"
}

variable "bedrock_model_id" {
  description = "Modelo o perfil de inferencia de Bedrock. Vacío = modo determinista sin LLM."
  type        = string
  default     = "us.anthropic.claude-haiku-4-5-20251001-v1:0"
}

variable "model_price_in_per_mtok" {
  description = "Precio USD por millón de tokens de entrada (para reportar el costo del análisis)."
  type        = number
  default     = 1
}

variable "model_price_out_per_mtok" {
  description = "Precio USD por millón de tokens de salida."
  type        = number
  default     = 5
}

variable "cost_tag_key" {
  description = "Tag de asignación de costos usado para atribuir el gasto (activado en Billing)."
  type        = string
  default     = "Project"
}

variable "log_retention_days" {
  description = "Retención de los logs de la Lambda."
  type        = number
  default     = 14
}

variable "tags" {
  description = "Tags obligatorios: Project, Environment, Owner, CostCenter."
  type        = map(string)
}
