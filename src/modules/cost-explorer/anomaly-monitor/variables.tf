variable "name" {
  description = "Nombre del monitor."
  type        = string
}

variable "monitor_dimension" {
  description = "Dimensión del monitor. AWS permite un solo monitor SERVICE por cuenta."
  type        = string
  default     = "SERVICE"
}

variable "tags" {
  description = "Tags del recurso (de utils/tagger)."
  type        = map(string)
}
