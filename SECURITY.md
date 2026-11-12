# Seguridad

## Reportar una vulnerabilidad

No abras un issue público. Usa **Security → Report a vulnerability** (GitHub private vulnerability
reporting) en este repositorio. Respuesta inicial en un máximo de 5 días hábiles.

## Qué nunca va en este repositorio

- Cuentas AWS, ARNs reales, perfiles o regiones por entorno: viven en `scripts/env/<entorno>.env` (ignorado).
- Configuración por entorno: vive en SSM Parameter Store (`/terraform-with-ia/<entorno>/<deployment>`).
- Secretos (tokens, passwords): SSM `SecureString`, leídos en runtime; nunca en el state ni en variables.
- State de Terraform, planes (`tfplan`, `plan.json`) ni archivos `*.tfvars`.

Si algo de esto llega a un commit, rota la credencial primero y después limpia el historial.

## Controles del repositorio

| Control | Dónde |
| --- | --- |
| Escaneo IaC (checkov) | `scripts/tf-check.sh`, hook del agente y CI |
| Detección de secretos (gitleaks) | `.pre-commit-config.yaml` |
| `apply`/`destroy` bloqueados para el agente | `.claude/settings.json` y `scripts/tf.sh` |
| `plan` con rol de solo lectura vía OIDC, sin secretos para forks | `.github/workflows/terraform-pr.yml` |
| Actualización de providers, módulos y actions | `.github/dependabot.yml` |
