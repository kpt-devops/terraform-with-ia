# Tabla DynamoDB con los defaults del repo. Implementación: terraform-aws-modules/dynamodb-table (aprobado en src/modules/catalog.md).
# Impone: PAY_PER_REQUEST, PITR activo, cifrado SSE y TTL opcional.
module "table" {
  # checkov:skip=CKV_TF_1: módulo del Terraform Registry fijado por versión según src/modules/catalog.md.
  # checkov:skip=CKV_AWS_119: cifrado SSE con la clave administrada por AWS; una tabla con datos sensibles debe pasar una CMK.
  source  = "terraform-aws-modules/dynamodb-table/aws"
  version = "~> 5.5"

  name         = var.name
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = var.hash_key
  attributes   = [{ name = var.hash_key, type = "S" }]

  point_in_time_recovery_enabled = true
  server_side_encryption_enabled = true
  deletion_protection_enabled    = var.deletion_protection

  ttl_enabled        = var.ttl_attribute != null
  ttl_attribute_name = coalesce(var.ttl_attribute, "ttl")

  tags = var.tags
}
