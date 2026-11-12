variable "name" {
  description = "Nombre del rol."
  type        = string
}

variable "description" {
  description = "Descripción del rol."
  type        = string
  default     = "Rol asumido por GitHub Actions vía OIDC"
}

variable "oidc_provider_arn" {
  description = "ARN del proveedor OIDC de GitHub (modules/iam/github-oidc-provider o uno existente)."
  type        = string
}

variable "subjects" {
  description = "Valores exactos del claim sub que pueden asumir el rol (sin comodines)."
  type        = list(string)

  validation {
    condition     = length(var.subjects) > 0 && alltrue([for s in var.subjects : startswith(s, "repo:") && !strcontains(s, "*")])
    error_message = "subjects debe tener al menos un valor 'repo:<owner>/<repo>:...' y ninguno puede usar '*'."
  }
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
