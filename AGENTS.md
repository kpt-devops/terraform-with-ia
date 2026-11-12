# terraform-with-ia — reglas para agentes

## Estructura
Cuatro carpetas en src/, cada una con un solo trabajo:
- src/modules/<servicio>/<variante>/: módulos reutilizables (child modules) con los recursos AWS
  definidos una vez. Cada uno es un wrapper de un módulo aprobado de la comunidad o un
  `resource "x" "this"` desde cero. Es el único lugar con bloques `resource` (salvo data sources
  e IAM policy documents).
- src/deployments/<deployment>/: un root module por deployment, con su propio state. Solo invoca
  src/modules/ y src/utils/. Nunca define `resource` ni llama módulos del registry.
- src/utils/: módulos de soporte. `environment` (entorno = workspace, guard y config desde SSM)
  y `tagger` (tags obligatorios). Todo deployment los usa.
- src/apps/<app>/: código de aplicación (Lambdas, scripts). Un deployment lo pasa a un módulo
  por variable: `source_path = "${path.module}/../../apps/<app>"`.
- No crees archivos .tf fuera de esas carpetas.

## Módulos: catálogo antes que código nuevo
- Antes de escribir, lee src/modules/catalog.md y sigue su orden: módulo propio → módulo
  aprobado de la comunidad (se envuelve como módulo propio nuevo) → módulo a explorar
  (proponerlo en el PR) → módulo desde cero con justificación.
- Nunca uses un módulo del registry que no esté en "Aprobados". Fija su `version` con la
  restricción del catálogo y verifica sus inputs con el Terraform MCP (get_module_details).
- Un módulo nuevo se registra en la tabla "Módulos propios" del catálogo en el mismo PR.

## Reutilización
- Otra cola, otro topic, otra función = otra llamada al mismo módulo de src/modules/, nunca
  una copia. Si son varias iguales en un deployment, `for_each` sobre un mapa.
- Deployment nuevo = carpeta nueva en src/deployments/ con versions.tf, provider.tf, main.tf,
  outputs.tf y config.example.json (copia la forma de src/deployments/sqs-orders/).
- Si cambias la dirección de un recurso existente (renombre, for_each), agrega un bloque `moved`.

## Fuente de verdad
- Antes de escribir un recurso o argumento, consulta el Terraform MCP
  (search_providers / get_provider_details). Nunca escribas un argumento de memoria.
- Usa la versión de provider fijada en el versions.tf del deployment; no la cambies sin pedirlo.
- Si un argumento pedido no existe en esa versión, dilo y no lo inventes.

## Convenciones
- Naming: <recurso>-<entorno> con el entorno de `module.env.environment`.
- Tags: siempre `module.tagger.tags` (Project, Environment, Owner, CostCenter).
- Cifrado en reposo siempre activo; nada público por defecto.

## Entornos
- El entorno es el workspace y lo elige scripts/tf.sh: `scripts/tf.sh <dev|prod> <deployment> <comando>`.
  No corras terraform directo en un deployment.
- Nunca crees carpetas, archivos ni tfvars por entorno. Los valores por entorno viven fuera del
  repo: en SSM (`/terraform-with-ia/<entorno>/<deployment>`, leído por utils/environment como
  `module.env.config`) y en scripts/env/<entorno>.env (perfil, región, cuenta).
- Una clave nueva de config va con `try(module.env.config.<clave>, <default>)` y se documenta
  en config.example.json. Nunca escribas cuentas, ARNs reales ni secretos en el repo.
- Secretos (tokens, passwords) no van en la config: la aplicación los lee en runtime de SSM.

## Definition of done
- scripts/tf-check.sh termina en 0.
- El PR cita qué consultó (provider, versión, módulo) y resume add/change/destroy por deployment.
- Si el plan trae destroy, detén el trabajo y pregunta.
- Nunca ejecutes apply, destroy, import ni state (tf.sh los bloquea dentro del agente).
