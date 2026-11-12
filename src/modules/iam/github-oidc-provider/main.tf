# Proveedor OIDC de GitHub Actions. Uno por cuenta AWS.
# Sin thumbprint_list: para GitHub, IAM valida con su propia CA de confianza.
resource "aws_iam_openid_connect_provider" "this" {
  url            = "https://token.actions.githubusercontent.com"
  client_id_list = ["sts.amazonaws.com"]
  tags           = var.tags
}
