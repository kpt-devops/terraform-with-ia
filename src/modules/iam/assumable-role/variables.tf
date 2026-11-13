variable "name" {
  description = "Nombre del rol."
  type        = string
}

variable "description" {
  description = "Descripción del rol."
  type        = string
}

variable "trusted_principal_arns" {
  description = "ARNs de principals IAM que pueden asumir el rol (cuenta, rol o usuario). Sin '*'."
  type        = list(string)

  validation {
    condition     = length(var.trusted_principal_arns) > 0 && alltrue([for a in var.trusted_principal_arns : startswith(a, "arn:aws:iam::") && !strcontains(a, "*")])
    error_message = "trusted_principal_arns debe tener ARNs IAM explícitos, sin '*'."
  }
}

variable "require_mfa" {
  description = "Exige MFA al asumir el rol. Con IAM Identity Center no aplica (la sesión ya trae MFA)."
  type        = bool
  default     = false
}

variable "managed_policy_arns" {
  description = "Políticas administradas a adjuntar."
  type        = list(string)
  default     = []
}

variable "inline_policy_json" {
  description = "Política inline adicional (JSON). null = sin política inline."
  type        = string
  default     = null
}

variable "max_session_duration" {
  description = "Duración máxima de la sesión en segundos."
  type        = number
  default     = 3600
}

variable "tags" {
  description = "Tags del recurso (de utils/tagger)."
  type        = map(string)
}
