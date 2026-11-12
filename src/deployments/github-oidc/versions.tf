terraform {
  required_version = ">= 1.6"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.28"
    }
  }

  # Estado remoto recomendado; con workspaces cada entorno queda en env:/<env>/<key>.
  # backend "s3" {
  #   bucket       = "<bucket-de-state>"
  #   key          = "deployments/github-oidc/terraform.tfstate"
  #   region       = "us-east-1"
  #   use_lockfile = true
  # }
}
