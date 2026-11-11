# terraform-with-ia

Repositorio de referencia: un agente de IA genera Terraform para AWS **sin alucinar**,
gracias a grounding (Terraform MCP + convenciones del repo) y un loop de validación
(`fmt`, `validate`, `tflint`, `checkov`) que lo obliga a corregirse antes de abrir un PR.

## Estructura

| Ruta | Para qué |
| --- | --- |
| `AGENTS.md` | Reglas para cualquier agente de código |
| `.mcp.json` | Terraform MCP Server (toolset `registry`, versión fijada) |
| `.claude/settings.json` | `apply`/`destroy`/`state`/`import` denegados + hook de validación |
| `.claude/skills/tf-builder/` | Flujo intención → PR |
| `scripts/tf-check.sh` | Validaciones; exit 2 devuelve el error al agente |
| `modules/sqs-with-dlq/` | Módulo de referencia |
| `modules/cost-explainer/` | Agente que explica anomalías de costo y las envía a Telegram |
| `demos/cost-explainer/` | Guía y scripts de la demo de FinOps agéntico |
| `envs/dev/` | Composición que usa los módulos (`cost-explainer` se activa con `enable_cost_explainer`) |
| `evals/tasks.md` | Tareas para medir alucinación |
| `.github/workflows/terraform-pr.yml` | Checks en todo PR; `plan` + infracost solo en PRs del repo, con rol read-only (OIDC) |

## Quickstart

Requisitos: Terraform ≥ 1.6, Docker, Claude Code, tflint, checkov.

```bash
cd terraform-with-ia
./scripts/tf-check.sh < /dev/null   # debe terminar en 0
claude                               # aprueba el servidor de .mcp.json
```

Prompt de ejemplo:

> Usa tf-builder: necesito una cola SQS con DLQ para el servicio payments en dev,
> con alarma si la DLQ recibe mensajes.

## Guardrails

- El agente nunca ejecuta `apply`; su entregable es un PR.
- El `plan` con credenciales corre solo en CI con un rol de solo lectura.
- La imagen del MCP está fijada por versión; no se usa `latest`.
# terraform-with-ia
