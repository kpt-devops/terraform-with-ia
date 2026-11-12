variable "project" {
  description = "Proyecto dueño de los recursos."
  type        = string
}

variable "owner" {
  description = "Equipo responsable."
  type        = string
  default     = "platform"
}

variable "cost_center" {
  description = "Centro de costos (tag de asignación de costos)."
  type        = string

  validation {
    condition     = contains(["platform", "finops", "demos"], var.cost_center)
    error_message = "cost_center debe ser uno de: platform, finops, demos."
  }
}
