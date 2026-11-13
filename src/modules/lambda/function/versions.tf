terraform {
  required_version = ">= 1.6"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 6.28" # mínimo que exige terraform-aws-modules/lambda 8.x
    }
  }
}
