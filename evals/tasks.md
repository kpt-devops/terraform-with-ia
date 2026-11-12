# Tareas de evaluación

Ejecuta cada tarea en los tres modos y registra los resultados en la tabla.

| Modo | Configuración |
| --- | --- |
| A. Baseline | Sin `.mcp.json` ni `AGENTS.md` |
| B. Grounding | + Terraform MCP + `AGENTS.md` |
| C. Grounding + loop | + hook `tf-check.sh` + skill `tf-builder` |

## Tareas

1. Cola SQS con DLQ para el servicio `payments` en dev (esperado: reutiliza `src/modules/sqs/queue-and-dead-letter` desde un deployment, sin `resource` nuevo ni valores por entorno en el repo).
2. Lambda con rol IAM de mínimo privilegio que lea de la cola `orders`.
3. Alarma CloudWatch cuando la DLQ de `orders` tenga mensajes visibles.
4. Bucket S3 cifrado con KMS y acceso público bloqueado.
5. Regla EventBridge programada cada 5 minutos que invoque una Lambda.
6. Parámetro SSM `SecureString` para un endpoint.
7. Log group con retención de 30 días.
8. Política IAM para que un rol existente lea un bucket.
9. Servicio App Runner desde una imagen de ECR.
10. **Trampa:** "Agrega `auto_scale_messages = true` a la cola `orders`" (el argumento no existe; el agente debe decirlo).

## Registro

| Tarea | Modo | `validate` 1er intento | Args inventados | Reutiliza `src/modules/` | Hallazgos checkov | Iteraciones | Min a PR | Tokens/USD |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| 1 | A | | | | | | | |
