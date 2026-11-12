# region y account_id los inyecta scripts/tf.sh desde scripts/env/<entorno>.env (no versionado).
variable "region" {
  description = "Región AWS del entorno."
  type        = string
}

variable "account_id" {
  description = "Cuenta AWS permitida para el entorno. Vacío = sin restricción."
  type        = string
  default     = ""
}

provider "aws" {
  region              = var.region
  allowed_account_ids = var.account_id == "" ? null : [var.account_id]
}
