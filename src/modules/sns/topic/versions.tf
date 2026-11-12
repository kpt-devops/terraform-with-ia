terraform {
  required_version = ">= 1.6"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 6.67" # mínimo que exige terraform-aws-modules/sns 7.x
    }
  }
}
