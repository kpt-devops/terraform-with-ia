terraform {
  required_version = ">= 1.6"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.67"
    }
  }

  # Estado remoto: un bucket por cuenta. bucket y region los pasa scripts/tf.sh desde
  # TF_STATE_BUCKET / TF_STATE_REGION del .env del entorno. Workspace = env:/<entorno>/<key>.
  backend "s3" {
    key          = "deployments/finops-cost-explainer/terraform.tfstate"
    use_lockfile = true
  }
}
