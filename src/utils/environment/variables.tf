variable "project" {
  description = "Nombre del deployment (carpeta en src/deployments/). Forma parte de la ruta del parámetro SSM."
  type        = string
}

variable "allowed_environments" {
  description = "Workspaces válidos."
  type        = list(string)
  default     = ["dev", "prod"]
}

variable "parameter_prefix" {
  description = "Prefijo de los parámetros SSM de configuración."
  type        = string
  default     = "/terraform-with-ia"
}
