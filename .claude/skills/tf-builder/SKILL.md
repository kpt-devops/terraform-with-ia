---
name: tf-builder
description: Genera infraestructura Terraform desde una intención en lenguaje natural, consultando el Terraform MCP y validando con tf-check antes de abrir un PR.
---
# tf-builder
1. Reformula la intención en requisitos (recurso, entorno, límites) y pregunta solo lo que falte.
2. Revisa src/modules/catalog.md: módulo propio primero. Si no existe, envuelve un módulo aprobado de la comunidad como módulo nuevo en src/modules/<servicio>/<variante>/; si solo hay uno "a explorar" o ninguno, consulta el MCP (search_modules / get_module_details) y propón la incorporación al catálogo en el PR.
3. Usa un deployment existente de src/deployments/ o crea uno nuevo con la forma de src/deployments/sqs-orders/: invoca solo ../../modules/... y ../../utils/{environment,tagger}.
4. Lo que cambie por entorno va como clave con `try(module.env.config.<clave>, <default>)` y en config.example.json; nunca en archivos por entorno.
5. Deja que el hook valide; máximo 3 intentos de corrección, luego explica el bloqueo. Para ver el plan usa `scripts/tf.sh <entorno> <deployment> plan` (requiere credenciales; nunca apply).
6. Crea una rama y abre el PR con: intención, fuentes consultadas, claves de config nuevas y resultado de los checks.
