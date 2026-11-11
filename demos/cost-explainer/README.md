# cost-explainer — de la alerta a la causa

Cuando AWS Cost Anomaly Detection (CAD) detecta una anomalía, esta demo explica **por qué**
ocurrió y lo envía a Telegram con evidencia: qué usage type subió, qué cambio de CloudTrail
coincide, qué proyecto (tag) absorbe el costo y cuánto costaría al mes.

```text
CAD (alerta IMMEDIATE) → SNS → Lambda cost-explainer → Bedrock (opcional) → Telegram
                                   │
                                   ├─ Cost Explorer: usage types antes vs durante + costo por tag
                                   └─ CloudTrail: cambios (no lecturas) del servicio en la ventana
```

El código junta la evidencia; el modelo solo la explica y debe citar ids de evidencia.
Si Bedrock no está disponible, la Lambda envía un resumen determinista.

La infraestructura vive en este repositorio como el módulo
[`modules/cost-explainer`](../../modules/cost-explainer), con las mismas convenciones y validaciones
(`tf-check.sh`, checkov) que el resto del repo. Esta carpeta contiene la guía y los scripts de la demo.

| Ruta | Para qué |
| --- | --- |
| `modules/cost-explainer/` | SNS, suscripción de CAD, Lambda, rol IAM de solo lectura |
| `modules/cost-explainer/lambda/handler.py` | Recolecta evidencia, explica y envía a Telegram |
| `envs/dev/` | Activa el módulo con `enable_cost_explainer = true` |
| `demos/cost-explainer/scripts/invoke-sample.sh` | Dispara la demo sin esperar una anomalía real |

## Requisitos

| Requisito | Notas |
| --- | --- |
| AWS CLI con credenciales de la cuenta | Desplegar en `us-east-1` |
| Terraform ≥ 1.6 | |
| Cost Anomaly Detection activo | Con al menos un monitor |
| Tag de costos activado en Billing | Por defecto `Project` (variable `cost_tag_key`) |
| Bot de Telegram | Se crea en el paso 1 |
| Acceso a un modelo en Bedrock | Opcional |
| Permisos de Amazon Q Developer en la consola | Para la parte de Amazon Q |

## Puesta en marcha (≈ 20 min)

### 1. Crear el bot de Telegram

1. En Telegram, abre **@BotFather**, envía `/newbot` y sigue los pasos. Guarda el token.
2. Abre un chat con tu bot (o agrégalo a un grupo) y envíale cualquier mensaje.
3. Obtén el `chat_id`:

```bash
curl -s "https://api.telegram.org/bot<TOKEN>/getUpdates" | python3 -m json.tool | grep -m1 -A2 '"chat"'
```

En grupos el `chat_id` es negativo (por ejemplo `-100123...`).

### 2. Guardar el token en SSM (fuera de Terraform)

```bash
aws ssm put-parameter --region us-east-1 --name /cost-explainer/telegram-bot-token \
  --type SecureString --value '<TOKEN>'
```

El token nunca queda en el state de Terraform ni en el repositorio.

### 3. (Opcional) Habilitar el modelo en Bedrock

En la consola de Bedrock (us-east-1) → **Model access**, habilita el modelo que usarás.
El valor por defecto es un perfil de inferencia de Claude Haiku; verifica el ID exacto en
**Bedrock → Inference profiles** y cámbialo en `bedrock_model_id` si hace falta.
Con `bedrock_model_id = ""` la demo funciona en modo determinista.

### 4. Desplegar

```bash
cd envs/dev
cp terraform.tfvars.example terraform.tfvars   # enable_cost_explainer = true y telegram_chat_id
```

CAD permite **un solo monitor por servicio** por cuenta. Si ya tienes uno, reutilízalo:

```bash
aws ce get-anomaly-monitors --query 'AnomalyMonitors[].[MonitorName,MonitorArn,MonitorDimension]' --output table
# copia el ARN en cost_anomaly_monitor_arn dentro de terraform.tfvars
```

```bash
../../scripts/tf-check.sh < /dev/null   # mismas validaciones que el hook del agente
terraform init
terraform apply
```

### 5. Probar

Desde la raíz del repo:

```bash
./demos/cost-explainer/scripts/invoke-sample.sh replay          # anomalía real más reciente (últimos 90 días)
./demos/cost-explainer/scripts/invoke-sample.sh uso             # evento simulado de Lambda
./demos/cost-explainer/scripts/invoke-sample.sh sin-evidencia   # el agente debe decir que no es concluyente
```

Los eventos simulados usan **tus datos reales** de Cost Explorer y CloudTrail, así que el
resultado depende de tu cuenta. Revisa el mensaje en Telegram y los logs en
`/aws/lambda/tfia-dev-cost-explainer`.

## Amazon Q: la investigación nativa de AWS

Desde junio de 2026, CAD incluye **Investigate with Amazon Q**: una explicación en lenguaje
natural que correlaciona Cost Explorer con CloudTrail para nombrar la API y la identidad que
causaron el cambio. No tiene cargo adicional; las consultas cross-account a CloudWatch Logs
Insights se cobran a tarifa estándar.

**Paso a paso**

1. Consola de AWS → **Billing and Cost Management** → **Cost Anomaly Detection** → pestaña **Anomalies**.
2. Abre una anomalía. En la página de detalle, pulsa **Investigate with Amazon Q**.
3. Q abre un chat con la anomalía como contexto y devuelve:
   - si el cambio es de **uso** (más actividad) o de **tarifa** (precio o descuento);
   - qué llamadas de API e identidades IAM lo originaron;
   - qué datos le faltaron, cuando no puede concluir.
4. Haz preguntas de seguimiento en el mismo chat, por ejemplo:
   - "Desglosa el aumento por servicio y región."
   - "¿El costo está concentrado en una cuenta o repartido en la organización?"
   - "¿Cómo se compara con los cambios recientes de esta cuenta?"

**Si no ves el botón:** tu usuario necesita permisos de Amazon Q Developer en la consola
(por ejemplo la política administrada `AmazonQFullAccess`).

**Para investigar anomalías de cuentas vinculadas**, Q necesita un trail de CloudTrail de
organización con entrega a CloudWatch Logs. Desde la cuenta de administración:

```bash
aws logs create-log-group --log-group-name /aws/cloudtrail/org

aws iam create-role --role-name CloudTrailToCWLogs --assume-role-policy-document \
  '{"Version":"2012-10-17","Statement":[{"Effect":"Allow","Principal":{"Service":"cloudtrail.amazonaws.com"},"Action":"sts:AssumeRole"}]}'

aws iam put-role-policy --role-name CloudTrailToCWLogs --policy-name write-logs --policy-document \
  '{"Version":"2012-10-17","Statement":[{"Effect":"Allow","Action":["logs:CreateLogStream","logs:PutLogEvents"],"Resource":"arn:aws:logs:us-east-1:<MGMT_ACCOUNT>:log-group:/aws/cloudtrail/org:*"}]}'

aws cloudtrail update-trail --name <TRAIL_DE_ORGANIZACION> \
  --cloud-watch-logs-log-group-arn "arn:aws:logs:us-east-1:<MGMT_ACCOUNT>:log-group:/aws/cloudtrail/org:*" \
  --cloud-watch-logs-role-arn "arn:aws:iam::<MGMT_ACCOUNT>:role/CloudTrailToCWLogs"
```

Si aún no existe un trail de organización, créalo primero (`aws cloudtrail create-trail
--is-organization-trail --is-multi-region-trail ...`, con su bucket S3). La ingesta en
CloudWatch Logs tiene costo: define una retención en el log group.

### Amazon Q vs cost-explainer

| | Amazon Q en CAD | cost-explainer |
| --- | --- | --- |
| Dónde se ve | Consola de AWS, a demanda | Telegram, automático |
| Qué cambió y quién | Sí (API + identidad IAM) | Sí (CloudTrail de la cuenta) |
| Cross-account | Sí, con trail de organización | No (solo la cuenta de la Lambda) |
| Proyecto o equipo (tags) | No | Sí |
| Proyección mensual | Por conversación | Sí, en el mensaje |
| Costo del análisis | Sin cargo adicional | Se muestra en cada mensaje |

Se complementan: cada mensaje de Telegram termina con un enlace **Profundizar con Amazon Q**
que abre la anomalía en la consola de CAD, donde está el botón *Investigate with Amazon Q*.
La investigación de Q no tiene API pública para traer su resultado a Telegram; su versión
automática (AWS FinOps Agent, en preview) solo entrega en Slack o Jira.

## Guion de la demo (≈ 12 min)

| Min | Paso | Qué se muestra |
| --- | --- | --- |
| 0–2 | Alerta clásica de CAD (email o consola) | Un porcentaje, sin explicación |
| 2–5 | **Investigate with Amazon Q** + una pregunta de seguimiento | El "por qué" nativo de AWS |
| 5–8 | `./demos/cost-explainer/scripts/invoke-sample.sh replay` | Mensaje en Telegram: causa, evidencia, proyecto, impacto mensual y enlace a Amazon Q |
| 8–10 | `./demos/cost-explainer/scripts/invoke-sample.sh sin-evidencia` | El agente admite que no es concluyente |
| 10–12 | Logs de la Lambda + pie del mensaje | Evidencia citada y costo del propio análisis |

**Antes de la demo:** ejecuta los tres modos una vez y guarda capturas como respaldo.

## Costos de la demo

| Componente | Costo aproximado |
| --- | --- |
| Cost Explorer API | USD 0.01 por request (3 por análisis) |
| Bedrock (Haiku) | Fracciones de centavo por análisis |
| Lambda, SNS, logs | Dentro de la capa gratuita en volumen de demo |
| CloudWatch Logs del trail de organización | Según volumen de eventos (opcional) |

## Limpieza

```bash
cd envs/dev
terraform destroy -target=module.cost_explainer   # o enable_cost_explainer = false + terraform apply
aws ssm delete-parameter --region us-east-1 --name /cost-explainer/telegram-bot-token
```

## Límites conocidos

- CloudTrail `LookupEvents` solo cubre la cuenta y región de la Lambda; para otras cuentas usa Amazon Q.
- El mapeo servicio → EventSource cubre los servicios más comunes (`EVENT_SOURCES` en `modules/cost-explainer/lambda/handler.py`).
- CAD necesita historial de gasto para detectar anomalías; no se puede forzar una anomalía real de forma fiable, por eso existen los modos de prueba.
