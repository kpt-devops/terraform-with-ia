# Catálogo de módulos

`src/modules/` es la **única carpeta de recursos AWS** del repo. Cada módulo vive en
`src/modules/<servicio>/<variante>/`, se define una vez y cualquier deployment lo reutiliza sin
escribir `resource`. Hay dos formas de construirlo:

- **Wrapper de la comunidad**: envuelve un módulo aprobado de
  [terraform-aws-modules](https://github.com/terraform-aws-modules) y fija los defaults del repo.
- **Desde cero**: `resource "<tipo>" "this"` cuando no hay un módulo aprobado que valga la pena.

Los deployments (`src/deployments/<deployment>/`) solo invocan módulos y utils. El código de
aplicación vive en `src/apps/`.

Antes de escribir código, revisa este catálogo en este orden:

1. **Módulos propios** (tabla siguiente): ya traen las convenciones del repo. Úsalos primero.
2. **Módulos aprobados** de la comunidad: se envuelven como módulo propio nuevo con la versión fijada.
3. **Módulos a explorar**: se consultan con el Terraform MCP (`search_modules` /
   `get_module_details`) y se proponen en un PR que los mueva a "Aprobados".
4. **Desde cero**: si nada de lo anterior aplica; el PR explica por qué.

Reglas:
- Nunca uses un módulo del registry que no esté en "Aprobados", y nunca desde un deployment.
- Fija siempre `version` con la restricción de esta tabla (`~> X.Y`: acepta parches y minors, no majors).
- checkov `CKV_TF_1` (pin por commit hash) aplica a fuentes git; para módulos del registry se
  omite con `# checkov:skip=CKV_TF_1` y la justificación en el bloque `module`.
- Antes de subir una versión, revisa el CHANGELOG del módulo y corre `scripts/tf-check.sh`.
- Un módulo nuevo se agrega a la tabla de módulos propios en el mismo PR.

## Módulos propios

| Necesidad | Ruta (`src/modules/...`) | Construcción | Qué impone |
| --- | --- | --- | --- |
| Cola SQS con DLQ | `sqs/queue-and-dead-letter` | Wrapper de `terraform-aws-modules/sqs/aws` `~> 5.2` | DLQ `<name>-dlq`, cifrado SSE, retención de la DLQ de 14 días |
| Topic SNS | `sns/topic` | Wrapper de `terraform-aws-modules/sns/aws` `~> 7.2` | Solo los servicios listados pueden publicar |
| Función Lambda | `lambda/function` | Wrapper de `terraform-aws-modules/lambda/aws` `~> 8.12` | X-Ray activo, retención de logs, código desde `src/apps/` |
| Monitor de anomalías de costo | `cost-explorer/anomaly-monitor` | Desde cero (`aws_ce_anomaly_monitor`) | Monitor dimensional por servicio |
| Suscripción de anomalías | `cost-explorer/anomaly-subscription` | Desde cero (`aws_ce_anomaly_subscription`) | Alerta inmediata a SNS por umbral en USD |
| Proveedor OIDC de GitHub | `iam/github-oidc-provider` | Desde cero (`aws_iam_openid_connect_provider`) | Uno por cuenta; sin thumbprint (IAM usa su CA para GitHub) |
| Rol para GitHub Actions | `iam/github-actions-role` | Desde cero (`aws_iam_role` + trust OIDC) | `aud` = sts, `sub` exacto sin comodines (validado), políticas administradas e inline |

Desde un deployment se invocan como `source = "../../modules/<servicio>/<variante>"`.

## Utils

| Ruta (`src/utils/...`) | Para qué |
| --- | --- |
| `environment` | Entorno = workspace, guard (falla en `default`) y config del deployment desde SSM |
| `tagger` | Tags obligatorios `Project`, `Environment`, `Owner`, `CostCenter` |

## Módulos aprobados (comunidad)

Fuente: [terraform-aws-modules](https://github.com/terraform-aws-modules). Versiones verificadas en el
Terraform Registry el 2026-11-10.

| Necesidad | `source` | `version` | Defaults del repo |
| --- | --- | --- | --- |
| Cola SQS | `terraform-aws-modules/sqs/aws` | `~> 5.2` | Solo vía `sqs/queue-and-dead-letter` |
| Bucket S3 | `terraform-aws-modules/s3-bucket/aws` | `~> 5.17` | Bloqueo de acceso público, cifrado, versionado en prod |
| Función Lambda | `terraform-aws-modules/lambda/aws` | `~> 8.12` | Solo vía `lambda/function` |
| Tabla DynamoDB | `terraform-aws-modules/dynamodb-table/aws` | `~> 5.5` | `PAY_PER_REQUEST`, PITR activo |
| Topic SNS | `terraform-aws-modules/sns/aws` | `~> 7.2` | Solo vía `sns/topic`; KMS salvo que el publicador no lo soporte |
| Clave KMS | `terraform-aws-modules/kms/aws` | `~> 4.2` | Rotación activa |
| Parámetro SSM | `terraform-aws-modules/ssm-parameter/aws` | `~> 2.1` | `SecureString` para secretos |
| Alarmas y log groups | `terraform-aws-modules/cloudwatch/aws` | `~> 5.7` | Retención explícita |

## Módulos a explorar

| Necesidad | `source` | Última versión | Motivo para evaluarlo |
| --- | --- | --- | --- |
| Reglas y schedules de EventBridge | `terraform-aws-modules/eventbridge/aws` | 4.3.3 | Automatizaciones FinOps programadas |
| Roles y políticas IAM | `terraform-aws-modules/iam/aws` | 6.8.2 | Roles IAM más complejos; el rol OIDC de CI ya existe como módulo propio |
| Step Functions | `terraform-aws-modules/step-functions/aws` | 5.1.1 | Flujos de remediación con aprobación |
| App Runner | `terraform-aws-modules/app-runner/aws` | 1.2.3 | Servicios web simples |
| VPC | `terraform-aws-modules/vpc/aws` | 6.7.3 | Solo si una carga necesita red privada |

## Ejemplo: agregar un módulo nuevo

Para un bucket S3, el módulo se crea una vez como wrapper y luego cualquier deployment lo usa:

```hcl
# src/modules/s3/bucket/main.tf
module "bucket" {
  # checkov:skip=CKV_TF_1: módulo del registry fijado por versión (src/modules/catalog.md)
  source  = "terraform-aws-modules/s3-bucket/aws"
  version = "~> 5.17"

  bucket                  = var.name
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
  versioning              = { enabled = var.versioning }
  tags                    = var.tags
}
```

```hcl
# src/deployments/<deployment>/main.tf
module "artifacts" {
  source     = "../../modules/s3/bucket"
  name       = "artifacts-${module.env.environment}"
  versioning = try(module.env.config.s3_versioning, false)   # valor por entorno en SSM
  tags       = module.tagger.tags
}
```
