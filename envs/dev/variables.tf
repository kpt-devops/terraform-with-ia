variable "region" {
  description = "Región AWS del entorno."
  type        = string
  default     = "us-east-1"
}

variable "project" {
  description = "Nombre del proyecto para naming y tags."
  type        = string
  default     = "tfia"
}

variable "owner" {
  description = "Equipo o persona responsable."
  type        = string
  default     = "platform"
}

# --- cost-explainer (demo de FinOps agéntico) ---

variable "enable_cost_explainer" {
  description = "Despliega el agente que explica anomalías de costo y las envía a Telegram."
  type        = bool
  default     = false
}

variable "telegram_chat_id" {
  description = "Chat ID de Telegram que recibe los análisis de costo."
  type        = string
  default     = ""

  validation {
    condition     = !var.enable_cost_explainer || var.telegram_chat_id != ""
    error_message = "telegram_chat_id es obligatorio cuando enable_cost_explainer = true."
  }
}

variable "cost_anomaly_monitor_arn" {
  description = "ARN de un monitor de CAD existente. Vacío = el módulo crea uno por servicio."
  type        = string
  default     = ""
}

variable "bedrock_model_id" {
  description = "Modelo o perfil de inferencia de Bedrock. Vacío = modo determinista."
  type        = string
  default     = "us.anthropic.claude-haiku-4-5-20251001-v1:0"
}
