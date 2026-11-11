---
name: tf-builder
description: Genera infraestructura Terraform desde una intención en lenguaje natural, consultando el Terraform MCP y validando con tf-check antes de abrir un PR.
---
# tf-builder
1. Reformula la intención en requisitos (recurso, entorno, límites) y pregunta solo lo que falte.
2. Busca un módulo en modules/; si no existe, consulta el MCP por el recurso y su versión.
3. Escribe el código en envs/<entorno>/ siguiendo AGENTS.md.
4. Deja que el hook valide; máximo 3 intentos de corrección, luego explica el bloqueo.
5. Crea una rama y abre el PR con: intención, fuentes consultadas y resultado de los checks.
