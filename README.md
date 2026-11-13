# terraform-with-ia

Repositorio de referencia: un agente de IA genera Terraform para AWS **sin alucinar**,
gracias a grounding (Terraform MCP + convenciones del repo) y un loop de validación
(`fmt`, `validate`, `tflint`, `checkov`) que lo obliga a corregirse antes de abrir un PR.

## Estructura

```text
src/
├── modules/<servicio>/<variante>/     # módulos reutilizables: wrappers de la comunidad o recursos desde cero
│   └── catalog.md                     # qué usar antes de construir: propios → aprobados → a explorar
├── deployments/<deployment>/          # un root module y un state por deployment; solo invoca modules y utils
├── utils/environment/                 # entorno = workspace, guard y config desde SSM
├── utils/tagger/                      # tags obligatorios
└── apps/<app>/                        # código de aplicación (ej. la Lambda cost-explainer)
scripts/
├── tf.sh                              # scripts/tf.sh <dev|prod> <deployment> <comando>
├── config-push.sh                     # sube config.<entorno>.json a SSM
├── tf-check.sh                        # fmt, validate, tflint y checkov; exit 2 devuelve el error al agente
└── env/example.env                    # plantilla de perfil, región y cuenta (los .env reales no se versionan)
```

| Ruta | Para qué |
| --- | --- |
| `AGENTS.md` | Reglas para cualquier agente de código |
| `.mcp.json` | Terraform MCP Server (escribir con la fuente vigente) y AWS MCP Server (revisar lo desplegado, solo lectura) |
| `.claude/settings.json` | `apply`/`destroy`/`state`/`import` denegados + hook de validación |
| `.claude/skills/tf-builder/` | Flujo intención → PR |
| `src/deployments/agent-readonly/` | Rol del agente para el AWS MCP Server: ve configuración, no datos ni secretos ([pasos](#revisar-la-infraestructura-con-el-aws-mcp-server)) |
| `demos/terraform-mcp/` | Guía y guion de la demo de IaC con IA (nivel 200) |
| `src/deployments/sqs-orders/` | Ejemplo mínimo: una cola con DLQ |
| `src/deployments/github-oidc/` | Bootstrap del CI: proveedor OIDC y rol de solo lectura para el `plan` ([pasos](#ci-con-oidc)) |
| `src/deployments/finops-cost-explainer/` | Demo de FinOps agéntico ([guía](demos/cost-explainer/README.md)) |
| `evals/tasks.md` | Tareas para medir alucinación |
| `SECURITY.md` | Cómo reportar vulnerabilidades y qué nunca se versiona |
| `.pre-commit-config.yaml` | Hooks locales: gitleaks + `tf-check.sh` antes de cada commit |
| `.github/dependabot.yml` | Actualizaciones semanales de providers, módulos y actions |
| `.github/workflows/terraform-pr.yml` | Checks en todo PR; `plan` + infracost por deployment y entorno solo en PRs del repo, con rol read-only (OIDC) |

## Quickstart

Requisitos: Terraform ≥ 1.6, Docker, Claude Code, tflint, checkov, pre-commit.

```bash
cd terraform-with-ia
pre-commit install                   # gitleaks + tf-check en cada commit
./scripts/tf-check.sh < /dev/null   # debe terminar en 0 (no necesita credenciales)
claude                               # aprueba el servidor de .mcp.json
```

Prompt de ejemplo:

> Usa tf-builder: necesito una cola SQS con DLQ para el servicio payments,
> con alarma si la DLQ recibe mensajes.

## Módulos y deployments

Un módulo se escribe una vez en `src/modules/` y los deployments lo invocan. Una segunda cola no
copia código: es otra llamada al mismo módulo.

```hcl
# src/deployments/sqs-orders/main.tf
module "sqs" {
  source            = "../../modules/sqs/queue-and-dead-letter"
  name              = "orders-${module.env.environment}"
  max_receive_count = try(module.env.config.max_receive_count, 5)
  tags              = module.tagger.tags
}
```

`src/modules/catalog.md` define qué usar y en qué orden: recursos propios → módulos aprobados de
[terraform-aws-modules](https://github.com/terraform-aws-modules) con versión fijada (se envuelven
como módulo propio) → a explorar (se proponen en un PR) → desde cero con justificación.

## Entornos sin duplicar código

Un mismo código para todos los entornos. El entorno es el workspace de Terraform y lo elige
`scripts/tf.sh`; los valores por entorno nunca entran al repo:

```bash
cp scripts/env/example.env scripts/env/dev.env                      # perfil, región, cuenta
cp src/deployments/sqs-orders/config.example.json src/deployments/sqs-orders/config.dev.json
./scripts/config-push.sh dev sqs-orders                             # -> SSM /terraform-with-ia/dev/sqs-orders
./scripts/tf.sh dev sqs-orders plan
```

| Pieza | Para qué |
| --- | --- |
| `scripts/tf.sh` | Carga `scripts/env/<entorno>.env`, selecciona el workspace `<entorno>` y bloquea `apply`/`destroy` dentro del agente |
| `utils/environment` | `environment = terraform.workspace`; falla si el workspace no es `dev` o `prod`; lee la config del deployment desde SSM |
| `module.env.config` | Valores por entorno (umbrales, reintentos, flags), leídos con `try(..., default)` |
| `allowed_account_ids` | Impide aplicar un entorno en una cuenta AWS que no le corresponde |
| Backend S3 | Un bucket por cuenta (`TF_STATE_BUCKET` en el `.env`; en CI, variable del GitHub Environment) y un state por deployment; con workspaces, cada entorno queda en `env:/<entorno>/...` |

## Revisar la infraestructura con el AWS MCP Server

El [AWS MCP Server](https://aws.amazon.com/blogs/aws/the-aws-mcp-server-is-now-generally-available) (gestionado
por AWS) le permite al agente comprobar que lo desplegado coincide con el código. Corre con un rol propio,
creado con Terraform, que lee configuración pero no datos, secretos ni permite escribir:

```bash
cp src/deployments/agent-readonly/config.example.json src/deployments/agent-readonly/config.dev.json
./scripts/config-push.sh dev agent-readonly
./scripts/tf.sh dev agent-readonly apply
./scripts/tf.sh dev agent-readonly output -raw agent_role_arn
```

```ini
# ~/.aws/config
[profile terraform-with-ia-agent]
role_arn       = <agent_role_arn>
source_profile = <tu perfil>
region         = us-east-1
```

| Capa | Control |
| --- | --- |
| IAM | `ReadOnlyAccess` + deny explícito de `s3:GetObject*`, `secretsmanager:GetSecretValue`, `ssm:GetParameter*`, `kms:Decrypt`, `sqs:ReceiveMessage`, lecturas de DynamoDB y `lambda:GetFunction` |
| Proxy | `mcp-proxy-for-aws-cli` fijado por versión con `--read-only` |
| Claude Code | `mcp__aws__run_script` denegado en `.claude/settings.json` |
| AGENTS.md | El AWS MCP solo verifica; los cambios van por código y PR |
| Auditoría | CloudTrail registra cada llamada; métricas en el namespace `AWS-MCP` |

Opcional a nivel de organización: una SCP con `aws:ViaAWSMCPService = true` que niegue escrituras aunque el
perfil tenga más permisos ([AWS Security Blog](https://aws.amazon.com/blogs/security/understanding-iam-for-managed-aws-mcp-servers)).

## CI con OIDC

El workflow no usa access keys: asume un rol de solo lectura por OIDC, creado con Terraform en
`src/deployments/github-oidc`. Se aplica a mano una vez por entorno:

```bash
cp src/deployments/github-oidc/config.example.json src/deployments/github-oidc/config.dev.json
# create_oidc_provider=false si el proveedor ya existe en la cuenta (por ejemplo, dev y prod en la misma)
./scripts/config-push.sh dev github-oidc
./scripts/tf.sh dev github-oidc apply
./scripts/tf.sh dev github-oidc output -raw plan_role_arn   # -> secreto AWS_PLAN_ROLE_ARN del environment dev
```

| Control | Cómo |
| --- | --- |
| Solo este repo y este environment asumen el rol | `sub = repo:kpt-devops/terraform-with-ia:environment:<entorno>`, sin comodines (validado en el módulo) |
| Solo lectura | `ReadOnlyAccess` + `ssm:GetParameter` sobre `/terraform-with-ia/<entorno>/*` |
| Forks sin acceso | El job `plan` no corre en PRs de forks y el `sub` de un fork no coincide |
| Prod con aprobación | GitHub Environment `prod` con *Required reviewers* |

## Guardrails

- El agente nunca ejecuta `apply`; su entregable es un PR. `tf.sh` también lo bloquea cuando corre dentro de Claude Code.
- Cuentas, ARNs y secretos nunca se versionan: viven en `scripts/env/*.env` (ignorado) y en SSM.
- El `plan` con credenciales corre solo en CI con un rol de solo lectura.
- La imagen del MCP está fijada por versión; no se usa `latest`.

## Licencia

[Apache License 2.0](LICENSE). Puedes usar, modificar y redistribuir el código, incluso con fines
comerciales, conservando el aviso de licencia. Incluye una concesión explícita de patentes; es la
misma licencia que usan los módulos de [terraform-aws-modules](https://github.com/terraform-aws-modules).
