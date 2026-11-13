# Wrapper propio de SNS. Implementación: terraform-aws-modules/sns (aprobado en src/modules/catalog.md).
# Impone: política mínima (solo los servicios listados pueden publicar) y tags.
module "topic" {
  # checkov:skip=CKV_TF_1: módulo del Terraform Registry fijado por versión según src/modules/catalog.md.
  # checkov:skip=CKV_AWS_26: kms_master_key_id es configurable; null solo cuando el publicador no admite KMS (ej. Cost Anomaly Detection).
  source  = "terraform-aws-modules/sns/aws"
  version = "~> 7.2"

  name              = var.name
  kms_master_key_id = var.kms_master_key_id

  topic_policy_statements = {
    for idx, service in var.publisher_services : "publisher_${idx}" => {
      sid     = "AllowServicePublish${idx}"
      actions = ["sns:Publish"]
      principals = [{
        type        = "Service"
        identifiers = [service]
      }]
    }
  }

  subscriptions = var.subscriptions
  tags          = var.tags
}
