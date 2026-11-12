# Bootstrap del CI: rol de solo lectura que el workflow terraform-pr asume vía OIDC para el plan.
# Se aplica a mano, una vez por entorno: scripts/tf.sh <entorno> github-oidc apply
# La salida plan_role_arn va al secreto AWS_PLAN_ROLE_ARN del GitHub Environment del mismo nombre.

locals {
  repository  = "kpt-devops/terraform-with-ia"
  environment = module.env.environment
  cfg         = module.env.config

  # El proveedor OIDC es uno por cuenta: si dev y prod comparten cuenta, solo uno lo crea.
  create_oidc_provider = try(local.cfg.create_oidc_provider, true)
  oidc_provider_arn    = local.create_oidc_provider ? module.oidc_provider[0].arn : data.aws_iam_openid_connect_provider.existing[0].arn
  state_bucket         = try(local.cfg.state_bucket, "")
}

module "env" {
  source  = "../../utils/environment"
  project = "github-oidc"
}

module "tagger" {
  source      = "../../utils/tagger"
  project     = "github-oidc"
  cost_center = "platform"
}

data "aws_caller_identity" "current" {}
data "aws_region" "current" {}

module "oidc_provider" {
  source = "../../modules/iam/github-oidc-provider"
  count  = local.create_oidc_provider ? 1 : 0

  tags = module.tagger.tags
}

data "aws_iam_openid_connect_provider" "existing" {
  count = local.create_oidc_provider ? 0 : 1
  url   = "https://token.actions.githubusercontent.com"
}

# Extra sobre ReadOnlyAccess: leer la config del repo en SSM (SecureString) y, si hay backend S3, el state.
data "aws_iam_policy_document" "plan" {
  statement {
    sid       = "ReadRepoConfig"
    actions   = ["ssm:GetParameter"]
    resources = ["arn:aws:ssm:${data.aws_region.current.region}:${data.aws_caller_identity.current.account_id}:parameter/terraform-with-ia/${local.environment}/*"]
  }

  statement {
    sid       = "DecryptRepoConfig"
    actions   = ["kms:Decrypt"]
    resources = ["arn:aws:kms:${data.aws_region.current.region}:${data.aws_caller_identity.current.account_id}:key/*"]

    condition {
      test     = "StringEquals"
      variable = "kms:ViaService"
      values   = ["ssm.${data.aws_region.current.region}.amazonaws.com"]
    }
  }

  dynamic "statement" {
    for_each = local.state_bucket == "" ? [] : [local.state_bucket]
    content {
      sid       = "ReadState"
      actions   = ["s3:ListBucket", "s3:GetObject"]
      resources = ["arn:aws:s3:::${statement.value}", "arn:aws:s3:::${statement.value}/*"]
    }
  }

  # use_lockfile: el plan crea y borra el .tflock junto al state.
  dynamic "statement" {
    for_each = local.state_bucket == "" ? [] : [local.state_bucket]
    content {
      sid       = "StateLock"
      actions   = ["s3:PutObject", "s3:DeleteObject"]
      resources = ["arn:aws:s3:::${statement.value}/*.tflock"]
    }
  }
}

module "plan_role" {
  source = "../../modules/iam/github-actions-role"

  name                = "gha-terraform-plan-${local.environment}"
  description         = "terraform plan desde GitHub Actions (${local.repository}, environment ${local.environment})"
  oidc_provider_arn   = local.oidc_provider_arn
  subjects            = ["repo:${local.repository}:environment:${local.environment}"]
  managed_policy_arns = ["arn:aws:iam::aws:policy/ReadOnlyAccess"]
  inline_policy_json  = data.aws_iam_policy_document.plan.json
  tags                = module.tagger.tags
}
