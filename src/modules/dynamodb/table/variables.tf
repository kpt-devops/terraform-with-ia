variable "name" {
  description = "Nombre de la tabla (<recurso>-<entorno>)."
  type        = string
}

variable "hash_key" {
  description = "Clave de partición (tipo string)."
  type        = string
}

variable "ttl_attribute" {
  description = "Atributo con la fecha de expiración (epoch en segundos). Null = sin TTL."
  type        = string
  default     = null
}

variable "deletion_protection" {
  description = "Protección contra borrado. Activar en prod."
  type        = bool
  default     = false
}

variable "tags" {
  description = "Tags obligatorios: Project, Environment, Owner, CostCenter."
  type        = map(string)
}
