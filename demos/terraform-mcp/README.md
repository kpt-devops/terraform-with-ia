# Demo: IaC con IA sin alucinaciones (nivel 200)

Un agente construye infraestructura AWS desde una intención en lenguaje natural sin inventar: consulta la
fuente (Terraform MCP), sigue las reglas del repo (AGENTS.md + catálogo), se corrige con el hook de validación
y, ya desplegado, verifica la infraestructura real con el AWS MCP Server.

| Dato | Valor |
| --- | --- |
| Nivel | 200 (buenas prácticas, para quien ya usa Terraform) |
| Duración | ≈ 25 min (10 de demo en vivo) |
| Preparación | ≈ 30 min la primera vez |
| Costo AWS | Centavos: una cola SQS + DLQ en dev |

Para validar la demo antes de presentarla, sigue [`escenarios.md`](escenarios.md): 8 escenarios con resultado esperado, criterio de aprobación y captura.

## Preparación

| Paso | Comando o acción | Para qué |
| --- | --- | --- |
| 1 | Terraform ≥ 1.6, Docker, `uv`, tflint, checkov, pre-commit, Claude Code | Herramientas |
| 2 | `pre-commit install` y `./scripts/tf-check.sh < /dev/null` | Debe terminar en 0 |
| 3 | `cp scripts/env/example.env scripts/env/dev.env` y editarlo | Perfil, región y cuenta de dev |
| 4 | `cp src/deployments/sqs-orders/config.example.json src/deployments/sqs-orders/config.dev.json` y `./scripts/config-push.sh dev sqs-orders` | Config de dev en SSM |
| 5 | `agent-readonly`: config, `config-push` y `./scripts/tf.sh dev agent-readonly apply` | Rol del agente para el AWS MCP |
| 6 | Perfil `terraform-with-ia-agent` en `~/.aws/config` (ver README) | Credenciales del AWS MCP |
| 7 | `./scripts/tf.sh dev sqs-orders apply` | La cola que el agente revisará |
| 8 | `claude` en la raíz, aprobar los servidores de `.mcp.json` y revisar `/mcp` | `terraform` y `aws` conectados |
| 9 | Ensayo completo y capturas de respaldo | Plan B si falla la red |

## Guion

| Min | Bloque | Qué se dice / se muestra |
| --- | --- | --- |
| 0–5 | El problema | La IA escribe Terraform desde la memoria: argumentos inventados, versiones viejas, recursos sin convenciones |
| 5–10 | La idea | El modelo razona; la verdad viene del registry (Terraform MCP), del repo (AGENTS.md + catálogo), de los validadores (hook) y de AWS (AWS MCP) |
| 10–14 | Demo 1: construir | Prompt A. El agente consulta el MCP, reutiliza `modules/sqs/queue-and-dead-letter`, el hook valida y abre el PR |
| 14–16 | Demo 2: la trampa | Prompt B. El agente dice que el argumento no existe |
| 16–20 | Demo 3: verificar | Prompt C. El agente revisa en AWS la cola desplegada y la compara con el código |
| 20–25 | Llévalo a tu equipo | Checklist de 5 pasos y preguntas |

## Prompts

**A. Construir**

> Usa tf-builder: necesito una cola SQS con DLQ para el servicio payments, con 3 reintentos antes de ir a la DLQ.

Qué debe pasar: consulta al Terraform MCP, crea `src/deployments/payments-queue/` que llama a
`../../modules/sqs/queue-and-dead-letter`, el valor por entorno va en `config.example.json`, el hook pasa
y el PR cita lo consultado.

**B. Trampa**

> Agrega `auto_scale_messages = true` a la cola de payments.

Qué debe pasar: el agente responde que ese argumento no existe en el provider ni en el módulo, y no lo escribe.

**C. Verificar la infraestructura**

> Revisa en AWS la cola orders-dev: ¿tiene DLQ, cifrado SSE, retención de 14 días en la DLQ, maxReceiveCount
> y los tags Project, Environment, Owner y CostCenter? Compáralo con src/deployments/sqs-orders y
> src/modules/sqs/queue-and-dead-letter y lista las diferencias.

Qué debe pasar: el agente usa `call_aws` (lectura), muestra qué coincide y qué no, y propone el cambio como
código, sin tocar AWS. Para lucirlo, cambia un tag a mano en la consola antes de la demo: el agente lo detecta.

## Checklist para tu equipo

1. `.mcp.json` versionado con el Terraform MCP (registry) y, si revisas lo desplegado, el AWS MCP con un rol de solo lectura.
2. `AGENTS.md` con estructura, convenciones y reglas anti-alucinación.
3. Catálogo de módulos: propios → aprobados de la comunidad → a explorar.
4. Hook de validación que devuelve el error al agente (exit 2).
5. El agente entrega PRs; `apply` queda fuera de su alcance y el CI planifica con un rol de solo lectura vía OIDC.

## Si algo falla en vivo

| Síntoma | Causa probable | Qué hacer |
| --- | --- | --- |
| `/mcp` muestra `terraform` desconectado | Docker apagado | Iniciar Docker y reabrir Claude Code |
| `/mcp` muestra `aws` con error de credenciales | Sesión SSO vencida o perfil mal escrito | `aws sso login` y revisar `~/.aws/config` |
| El hook tarda mucho | `terraform init` en cada deployment | Ensayar antes para tener `.terraform/` en caché |
| Sin red | — | Usar las capturas del ensayo |

## Limpieza

```bash
./scripts/tf.sh dev sqs-orders destroy
./scripts/tf.sh dev agent-readonly destroy
aws ssm delete-parameter --name /terraform-with-ia/dev/sqs-orders
aws ssm delete-parameter --name /terraform-with-ia/dev/agent-readonly
```
