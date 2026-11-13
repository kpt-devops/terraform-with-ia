# Pruebas offline del rol para GitHub Actions (OIDC): sin credenciales AWS (mock_provider).
# Cubren la validación de subjects (exactos, sin comodines) y las condiciones aud/sub de la
# trust policy. mock_data fija un JSON válido para aws_iam_policy_document (si no, el mock
# devuelve un string aleatorio que aws_iam_role rechaza); las aserciones van sobre los
# bloques statement/condition del data source, que son deterministas.

mock_provider "aws" {
  mock_data "aws_iam_policy_document" {
    defaults = {
      json = "{\"Version\":\"2012-10-17\",\"Statement\":[]}"
    }
  }
}

variables {
  name              = "gha-test"
  oidc_provider_arn = "arn:aws:iam::111111111111:oidc-provider/token.actions.githubusercontent.com"
  subjects          = ["repo:acme/infra:environment:dev"]
  tags              = { Project = "terraform-with-ia" }
}

run "rechaza_sub_con_comodin" {
  command = plan

  variables {
    subjects = ["repo:acme/infra:*"]
  }

  expect_failures = [var.subjects]
}

run "rechaza_sub_sin_prefijo_repo" {
  command = plan

  variables {
    subjects = ["acme/infra:ref:refs/heads/main"]
  }

  expect_failures = [var.subjects]
}

run "rechaza_subjects_vacio" {
  command = plan

  variables {
    subjects = []
  }

  expect_failures = [var.subjects]
}

run "trust_policy_exige_aud_y_sub_exactos" {
  command = plan

  variables {
    subjects = ["repo:acme/infra:environment:dev", "repo:acme/infra:ref:refs/heads/main"]
  }

  assert {
    condition     = toset(data.aws_iam_policy_document.trust.statement[0].actions) == toset(["sts:AssumeRoleWithWebIdentity"])
    error_message = "La única acción permitida debe ser sts:AssumeRoleWithWebIdentity."
  }

  assert {
    condition     = one([for p in data.aws_iam_policy_document.trust.statement[0].principals : sort(p.identifiers) if p.type == "Federated"]) == tolist([var.oidc_provider_arn])
    error_message = "El principal debe ser solo el proveedor OIDC recibido (Federated)."
  }

  assert {
    condition = anytrue([
      for c in data.aws_iam_policy_document.trust.statement[0].condition :
      c.test == "StringEquals" && c.variable == "token.actions.githubusercontent.com:aud" && length(c.values) == 1 && contains(c.values, "sts.amazonaws.com")
    ])
    error_message = "La trust policy debe exigir aud = sts.amazonaws.com con StringEquals."
  }

  assert {
    condition = anytrue([
      for c in data.aws_iam_policy_document.trust.statement[0].condition :
      c.test == "StringEquals" && c.variable == "token.actions.githubusercontent.com:sub" && sort(c.values) == sort(var.subjects)
    ])
    error_message = "La trust policy debe exigir sub exacto (StringEquals) con los subjects recibidos."
  }

  assert {
    condition     = alltrue([for c in data.aws_iam_policy_document.trust.statement[0].condition : c.test != "StringLike"])
    error_message = "La trust policy no debe usar StringLike (permitiría comodines)."
  }
}
