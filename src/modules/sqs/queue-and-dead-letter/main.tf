# Cola SQS + DLQ con los defaults del repo. Implementación: terraform-aws-modules/sqs (aprobado en src/modules/catalog.md).
module "queue" {
  # checkov:skip=CKV_TF_1: módulo del Terraform Registry fijado por versión según src/modules/catalog.md; el hash de commit aplica a fuentes git.
  source  = "terraform-aws-modules/sqs/aws"
  version = "~> 5.2"

  name                       = var.name
  visibility_timeout_seconds = var.visibility_timeout_seconds
  message_retention_seconds  = var.message_retention_seconds
  sqs_managed_sse_enabled    = true

  create_dlq                    = true
  dlq_name                      = "${var.name}-dlq"
  dlq_sqs_managed_sse_enabled   = true
  dlq_message_retention_seconds = 1209600 # 14 días, el máximo de SQS
  redrive_policy = {
    maxReceiveCount = var.max_receive_count
  }

  tags = var.tags
}
