# Config por entorno fuera del repo: un parámetro SSM (JSON) por entorno y deployment.
# El entorno es el workspace, que fija scripts/tf.sh.
locals {
  environment    = terraform.workspace
  parameter_name = "${var.parameter_prefix}/${local.environment}/${var.project}"
}

resource "terraform_data" "guard" {
  lifecycle {
    precondition {
      condition     = contains(var.allowed_environments, local.environment)
      error_message = "Workspace '${local.environment}' no válido. Usa scripts/tf.sh <dev|prod> <deployment> <comando>."
    }
  }
}

data "aws_ssm_parameter" "config" {
  name            = local.parameter_name
  with_decryption = true
  depends_on      = [terraform_data.guard]
}
