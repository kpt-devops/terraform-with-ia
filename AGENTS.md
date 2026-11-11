# terraform-with-ia — reglas para agentes

## Fuente de verdad
- Antes de escribir un recurso o argumento, consulta el Terraform MCP
  (search_providers / get_provider_details). Nunca escribas un argumento de memoria.
- Usa la versión de provider fijada en envs/*/versions.tf; no la cambies.
- Si un argumento pedido no existe en esa versión, dilo y no lo inventes.

## Convenciones
- Reutiliza módulos de modules/ antes de crear recursos sueltos
  (una cola SQS siempre con modules/sqs-with-dlq).
- Naming: <proyecto>-<entorno>-<recurso>.
- Tags obligatorios: Project, Environment, Owner, CostCenter.
- Cifrado en reposo siempre activo; nada público por defecto.
- Nunca renombres un recurso existente sin un bloque `moved`.

## Definition of done
- scripts/tf-check.sh termina en 0.
- El PR cita qué consultó (provider, versión, módulo) y resume add/change/destroy.
- Si el plan trae destroy, detén el trabajo y pregunta.
