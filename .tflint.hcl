plugin "terraform" {
  enabled = true
  preset  = "recommended"
}

# Reglas específicas de AWS (opcional): fija la versión vigente del ruleset.
# plugin "aws" {
#   enabled = true
#   version = "<versión>"
#   source  = "github.com/terraform-linters/tflint-ruleset-aws"
# }
