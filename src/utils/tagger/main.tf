locals {
  tags = {
    Project     = var.project
    Environment = terraform.workspace
    Owner       = var.owner
    CostCenter  = var.cost_center
  }
}
