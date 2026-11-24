# dlq-approval — una DLQ que pide permiso antes de reprocesar

Cuando llegan mensajes a la DLQ de una cola, una **Lambda durable function** avisa por Telegram,
**espera tu OK sin cobrar cómputo** (hasta 24 h) y, solo si apruebas, devuelve los mensajes a la
cola original con un redrive de SQS.

```text
cola orders → consumidor (falla N veces) → DLQ → CloudWatch alarm → EventBridge → starter
                                                                                   │
        Telegram ◄── Lambda durable (espera) ◄──────────────────────────────────────┘
           │ clic                     ▲ callback
           └──► webhook (Function URL) ┘          → redrive DLQ → cola orders
```

**Fase 1** (este estado del repo): aprobación + redrive completo.
Siguientes fases: diagnóstico (trigger apagado y errores en logs) y redrive canario.

| Ruta | Para qué |
| --- | --- |
| `src/deployments/sqs-orders/` | Cola, DLQ y el consumidor con fallos por mensaje y logs JSON |
| `src/deployments/dlq-approval/` | Alarma, regla de EventBridge, starter, función durable, webhook y tabla de referencias |
| `src/apps/orders-consumer/handler.py` | Consumidor: registra cada error con el `messageId` |
| `src/apps/dlq-approval/workflow.py` | Función durable: inspecciona, pide aprobación, hace el redrive y avisa el resultado |
| `src/apps/dlq-approval/starter.py` | Inicia la ejecución durable con un nombre idempotente (EventBridge no puede enviarlo) |
| `src/apps/dlq-approval/webhook.py` | Recibe el clic de Telegram y completa el callback |
| `demos/dlq-approval/scripts/send-orders.sh` | Envía pedidos válidos o rotos a la cola |

## Requisitos

| Requisito | Notas |
| --- | --- |
| AWS CLI con credenciales de la cuenta | `us-east-1` (durable functions disponible desde diciembre de 2025) |
| Terraform ≥ 1.6 y AWS provider ≥ 6.28 | El provider ya está fijado en el deployment |
| Deployment `sqs-orders` aplicado | Con el consumidor de este PR |
| Bot de Telegram | Puede ser el de cost-explainer, pero un bot admite **un solo webhook** |

## Puesta en marcha (≈ 25 min)

### 1. Bot de Telegram y chat_id

Si ya tienes el bot y el `chat_id` de la demo cost-explainer, sáltate este paso.
Si no: `@BotFather` → `/newbot`, envía un mensaje al bot y obtén el `chat_id` con
`getUpdates` **antes** de registrar el webhook (con webhook activo, `getUpdates` deja de responder).

```bash
curl -s "https://api.telegram.org/bot<TOKEN>/getUpdates" | python3 -m json.tool | grep -m1 -A2 '"chat"'
```

### 2. Secretos en SSM (fuera de Terraform)

```bash
aws ssm put-parameter --region us-east-1 --type SecureString \
  --name /dlq-approval/telegram-bot-token --value '<TOKEN>'
aws ssm put-parameter --region us-east-1 --type SecureString \
  --name /dlq-approval/telegram-webhook-secret --value "$(openssl rand -hex 32)"
```

El secreto del webhook es el que Telegram envía en cada llamada (`X-Telegram-Bot-Api-Secret-Token`);
la función rechaza cualquier llamada sin él.

### 3. Config de los deployments

```bash
cp src/deployments/sqs-orders/config.example.json src/deployments/sqs-orders/config.dev.json
cp src/deployments/dlq-approval/config.example.json src/deployments/dlq-approval/config.dev.json
# edita telegram_chat_id en dlq-approval/config.dev.json
./scripts/config-push.sh dev sqs-orders
./scripts/config-push.sh dev dlq-approval
```

### 4. Validar y desplegar

```bash
./scripts/tf-check.sh < /dev/null
./scripts/tf.sh dev sqs-orders plan    && ./scripts/tf.sh dev sqs-orders apply
./scripts/tf.sh dev dlq-approval plan  && ./scripts/tf.sh dev dlq-approval apply
```

### 5. Registrar el webhook en Telegram

```bash
URL=$(./scripts/tf.sh dev dlq-approval output -raw webhook_url)
SECRET=$(aws ssm get-parameter --region us-east-1 --with-decryption \
  --name /dlq-approval/telegram-webhook-secret --query Parameter.Value --output text)
curl -s "https://api.telegram.org/bot<TOKEN>/setWebhook" \
  -d "url=$URL" -d "secret_token=$SECRET" -d 'allowed_updates=["callback_query"]'
```

## Probar (guion de la demo)

1. **Introducir un bug en el consumidor.** En `src/deployments/sqs-orders/config.dev.json`,
   `"consumer_simulate_bug": true`, y luego:

   ```bash
   ./scripts/config-push.sh dev sqs-orders && ./scripts/tf.sh dev sqs-orders apply
   ```

2. **Enviar pedidos.** Fallan por el bug; con `maxReceiveCount = 5` y visibility timeout de 30 s,
   llegan a la DLQ en unos 3 minutos.

   ```bash
   ./demos/dlq-approval/scripts/send-orders.sh dev 5 validos
   ```

3. **Esperar el aviso.** La alarma pasa a ALARM con el primer mensaje visible en la DLQ (las métricas
   de SQS pueden tardar unos minutos) y llega el mensaje a Telegram con **Reprocesar** / **Esperar**.
4. **Ver la pausa.** Consola de Lambda → `dlq-approval-dev-workflow` → **Durable executions**: la
   ejecución está en espera y no cobra cómputo.
5. **Corregir.** `"consumer_simulate_bug": false`, `config-push` y `apply`.
6. **Clic en Reprocesar.** El webhook completa el callback, la función reanuda, hace el redrive y
   avisa cuántos mensajes movió. Los 5 pedidos se procesan bien.

Si eliges **Esperar** o nadie responde en 24 h, no se toca nada y la alarma sigue en ALARM.

Para ver por qué hace falta el canario (fase 3): envía pedidos `sin-monto` y aprueba sin corregir;
los mensajes vuelven a fallar y regresan a la DLQ.

```bash
./demos/dlq-approval/scripts/send-orders.sh dev 5 sin-monto
```

## Notas de diseño

| Decisión | Por qué |
| --- | --- |
| Starter entre EventBridge y la durable | EventBridge no puede enviar `DurableExecutionName`; la starter lo arma con el id del evento (idempotencia) |
| La durable se invoca por el alias `live` | Cada ejecución queda atada a su versión aunque se publique código nuevo mientras espera |
| Referencia corta del botón en DynamoDB (TTL) | `callback_data` de Telegram admite 64 bytes y un callback id llega a 1024 |
| `DeleteItem` al usar la referencia | Un segundo clic no hace nada |
| SDK de durable incluido en el runtime | Suficiente para la demo; en producción conviene empaquetarlo (`aws-durable-execution-sdk-python`) para fijar la versión |
