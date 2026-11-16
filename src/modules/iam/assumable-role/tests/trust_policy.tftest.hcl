# Pruebas offline del rol asumible: sin credenciales AWS (mock_provider).
# Cubren la validación de trusted_principal_arns y la condición MFA de la trust policy.
# Con mock_provider el JSON de aws_iam_policy_document sería un string aleatorio (y
# aws_iam_role lo rechaza), así que mock_data le da un JSON válido fijo y las aserciones
# van sobre los bloques statement/condition del data source (entradas deterministas).

mock_provider "aws" {
  mock_data "aws_iam_policy_document" {
    defaults = {
      json = "{\"Version\":\"2012-10-17\",\"Statement\":[]}"
    }
  }
}

variables {
  name                   = "test-role"
  description            = "Rol de prueba"
  trusted_principal_arns = ["arn:aws:iam::111111111111:root"]
  tags                   = { Project = "terraform-with-ia" }
}

run "rechaza_comodin_en_principals" {
  command = plan

  variables {
    trusted_principal_arns = ["*"]
  }

  expect_failures = [var.trusted_principal_arns]
}

run "rechaza_arn_no_iam" {
  command = plan

  variables {
    trusted_principal_arns = ["arn:aws:sts::111111111111:assumed-role/x/y"]
  }

  expect_failures = [var.trusted_principal_arns]
}

run "rechaza_lista_vacia" {
  command = plan

  variables {
    trusted_principal_arns = []
  }

  expect_failures = [var.trusted_principal_arns]
}

run "sin_mfa_no_hay_condicion_ni_inline" {
  command = plan

  assert {
    condition     = length(data.aws_iam_policy_document.trust.statement[0].condition) == 0
    error_message = "Sin require_mfa la trust policy no debe tener condiciones."
  }

  assert {
    condition     = length(aws_iam_role_policy.inline) == 0
    error_message = "Con inline_policy_json = null no debe crearse política inline."
  }
}

run "con_mfa_exige_multifactor" {
  command = plan

  variables {
    require_mfa        = true
    inline_policy_json = "{\"Version\":\"2012-10-17\",\"Statement\":[]}"
  }

  assert {
    condition = anytrue([
      for c in data.aws_iam_policy_document.trust.statement[0].condition :
      c.test == "Bool" && c.variable == "aws:MultiFactorAuthPresent" && length(c.values) == 1 && contains(c.values, "true")
    ])
    error_message = "require_mfa = true debe agregar Bool aws:MultiFactorAuthPresent = true."
  }

  assert {
    condition     = one([for p in data.aws_iam_policy_document.trust.statement[0].principals : sort(p.identifiers) if p.type == "AWS"]) == sort(["arn:aws:iam::111111111111:root"])
    error_message = "Los principals de confianza deben ser exactamente los ARNs recibidos."
  }

  assert {
    condition     = length(aws_iam_role_policy.inline) == 1 && aws_iam_role_policy.inline[0].name == "test-role-inline"
    error_message = "Con inline_policy_json definido debe crearse una política inline <name>-inline."
  }
}
