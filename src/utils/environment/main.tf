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

# Sin depends_on al guard: haría que la lectura se difiera al apply en el primer plan y la config
# quedaría desconocida (falla cualquier count/for_each que dependa de ella). El mismo guard va como
# precondition del data source, que se evalúa antes de leer el parámetro.
data "aws_ssm_parameter" "config" {
  name            = local.parameter_name
  with_decryption = true

  lifecycle {
    precondition {
      condition     = contains(var.allowed_environments, local.environment)
      error_message = "Workspace '${local.environment}' no válido. Usa scripts/tf.sh <dev|prod> <deployment> <comando>."
    }
  }
}
