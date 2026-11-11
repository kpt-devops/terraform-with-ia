"""cost-explainer: explica anomalías de AWS Cost Anomaly Detection y las envía a Telegram.

Regla de diseño: el código junta la evidencia (Cost Explorer, CloudTrail, tags);
el modelo solo la explica y debe citar ids de evidencia. Sin modelo configurado,
usa un resumen determinista.
"""
import datetime as dt
import html
import json
import os
import urllib.parse
import urllib.request

import boto3

CE = boto3.client("ce", region_name="us-east-1")
SSM = boto3.client("ssm")

MODEL_ID = os.environ.get("BEDROCK_MODEL_ID", "")
TAG_KEY = os.environ.get("COST_TAG_KEY", "Project")
CHAT_ID = os.environ.get("TELEGRAM_CHAT_ID", "")
TOKEN_PARAM = os.environ.get("TELEGRAM_TOKEN_PARAM", "")
PRICE_IN = float(os.environ.get("MODEL_PRICE_IN_PER_MTOK", "1.0"))
PRICE_OUT = float(os.environ.get("MODEL_PRICE_OUT_PER_MTOK", "5.0"))
DRY_RUN = os.environ.get("DRY_RUN", "false").lower() == "true"
CE_REQUEST_USD = 0.01  # cada request a la API de Cost Explorer cuesta USD 0.01

# Servicio (como lo nombra Cost Explorer) -> EventSource de CloudTrail
EVENT_SOURCES = {
    "AWS Lambda": "lambda.amazonaws.com",
    "Amazon Elastic Compute Cloud - Compute": "ec2.amazonaws.com",
    "EC2 - Other": "ec2.amazonaws.com",
    "Amazon Simple Queue Service": "sqs.amazonaws.com",
    "Amazon Simple Storage Service": "s3.amazonaws.com",
    "Amazon Relational Database Service": "rds.amazonaws.com",
    "Amazon DynamoDB": "dynamodb.amazonaws.com",
    "AmazonCloudWatch": "logs.amazonaws.com",
    "Amazon OpenSearch Service": "es.amazonaws.com",
    "AWS Step Functions": "states.amazonaws.com",
    "AWS Glue": "glue.amazonaws.com",
    "Amazon Athena": "athena.amazonaws.com",
    "Amazon Bedrock": "bedrock.amazonaws.com",
    "AWS App Runner": "apprunner.amazonaws.com",
}

SYSTEM_PROMPT = (
    "Eres un analista FinOps. Explica la causa probable de una anomalía de costo en AWS "
    "usando SOLO la evidencia JSON que recibes. Cada afirmación debe apoyarse en ids de "
    "'ids_validos'. Clasifica el cambio como 'uso' (más recursos o actividad), 'tarifa' "
    "(mismo uso a otro precio o descuento) o 'no_concluyente' si la evidencia no alcanza. "
    "No inventes recursos, personas ni cifras. Responde solo un objeto JSON con las claves: "
    "tipo, causa (máx. 2 frases), evidencia (lista de ids), confianza (alta|media|baja), "
    "proyecto, accion_sugerida (1 frase), faltante (qué dato cerraría la duda o vacío)."
)


def handler(event, context):
    account_id = context.invoked_function_arn.split(":")[4] if context else ""
    results = []
    for anomaly in _anomalies_from_event(event):
        evidence, index, ce_calls = collect_evidence(anomaly, account_id)
        verdict, usage = explain(anomaly, evidence, index)
        cost = (
            ce_calls * CE_REQUEST_USD
            + usage["input"] / 1e6 * PRICE_IN
            + usage["output"] / 1e6 * PRICE_OUT
        )
        text = render(anomaly, verdict, index, cost)
        if DRY_RUN:
            print(text)
        else:
            send_telegram(text)
        results.append({"anomaly_id": anomaly["id"], "verdict": verdict, "costo_usd": round(cost, 4)})
    print(json.dumps(results, ensure_ascii=False, default=str))
    return {"processed": len(results), "results": results}


# ---------- Entrada ----------

def _anomalies_from_event(event):
    if "Records" in event:  # alerta IMMEDIATE de CAD vía SNS
        for record in event["Records"]:
            yield _normalize(json.loads(record.get("Sns", {}).get("Message", "{}")))
    elif event.get("replay_last"):  # demo con una anomalía real de la cuenta
        yield _latest_anomaly(event.get("monitor_arn"))
    else:  # mensaje de CAD invocado directamente
        yield _normalize(event)


def _latest_anomaly(monitor_arn=None):
    today = dt.date.today()
    params = {"DateInterval": {"StartDate": (today - dt.timedelta(days=90)).isoformat(),
                               "EndDate": today.isoformat()}}
    if monitor_arn:
        params["MonitorArn"] = monitor_arn
    anomalies = CE.get_anomalies(**params).get("Anomalies", [])
    if not anomalies:
        raise RuntimeError("No hay anomalías en los últimos 90 días; usa el evento de ejemplo.")
    return _normalize(max(anomalies, key=lambda a: a.get("AnomalyStartDate", "")))


def _get(d, name, default=None):
    """Lee la clave en camelCase (SNS) o PascalCase (API)."""
    if not isinstance(d, dict):
        return default
    for key in (name, name[0].upper() + name[1:]):
        if d.get(key) is not None:
            return d[key]
    return default


def _normalize(raw):
    impact = _get(raw, "impact", {}) or {}
    causes = [{
        "service": _get(rc, "service", ""),
        "region": _get(rc, "region", ""),
        "usage_type": _get(rc, "usageType", ""),
        "account": _get(rc, "linkedAccount", ""),
    } for rc in (_get(raw, "rootCauses", []) or [])]
    start = str(_get(raw, "anomalyStartDate", "") or "")[:10]
    end = str(_get(raw, "anomalyEndDate", "") or "")[:10]
    return {
        "id": _get(raw, "anomalyId", "sin-id"),
        "start": start,
        "end": end or start,
        "total_impact": float(_get(impact, "totalImpact", _get(impact, "maxImpact", 0)) or 0),
        "pct": _get(impact, "totalImpactPercentage"),
        "root_causes": causes,
        "link": _get(raw, "anomalyDetailsLink", "") or _console_link(raw),
    }


def _console_link(raw):
    """Enlace a la anomalía en la consola de CAD (donde está 'Investigate with Amazon Q')."""
    monitor_arn = _get(raw, "monitorArn", "")
    anomaly_id = _get(raw, "anomalyId", "")
    if not monitor_arn or not anomaly_id:
        return "https://console.aws.amazon.com/cost-management/home#/anomaly-detection"
    monitor_id = monitor_arn.rsplit("/", 1)[-1]
    return ("https://console.aws.amazon.com/cost-management/home#/anomaly-detection/"
            f"monitors/{monitor_id}/anomalies/{anomaly_id}")


# ---------- Evidencia ----------

def _date(value):
    try:
        return dt.date.fromisoformat(str(value)[:10])
    except ValueError:
        return None


def _cost_by(start, end, flt, group):
    resp = CE.get_cost_and_usage(
        TimePeriod={"Start": start.isoformat(), "End": end.isoformat()},
        Granularity="DAILY", Metrics=["UnblendedCost"], Filter=flt, GroupBy=[group])
    totals = {}
    for period in resp.get("ResultsByTime", []):
        for group_row in period.get("Groups", []):
            key = group_row["Keys"][0]
            totals[key] = totals.get(key, 0.0) + float(group_row["Metrics"]["UnblendedCost"]["Amount"])
    return totals


def _cloudtrail(source, region, start, end):
    client = boto3.client("cloudtrail", region_name=region)
    resp = client.lookup_events(
        LookupAttributes=[{"AttributeKey": "EventSource", "AttributeValue": source}],
        StartTime=dt.datetime.combine(start, dt.time.min, tzinfo=dt.timezone.utc),
        EndTime=dt.datetime.combine(end, dt.time.min, tzinfo=dt.timezone.utc),
        MaxResults=50)
    events = []
    for e in resp.get("Events", []):
        try:
            detail = json.loads(e.get("CloudTrailEvent", "{}"))
        except ValueError:
            detail = {}
        if detail.get("readOnly", True):
            continue  # solo cambios (Create/Update/Put...), no lecturas
        events.append({
            "id": f"ct:{e['EventId']}",
            "evento": e["EventName"],
            "hora": e["EventTime"].isoformat(timespec="minutes"),
            "usuario": e.get("Username", ""),
            "recursos": [r.get("ResourceName", "") for r in e.get("Resources", [])][:3],
        })
        if len(events) >= 10:
            break
    return events


def collect_evidence(anomaly, account_id):
    index, ce_calls = {}, 0
    evidence = {"uso": [], "tags": [], "cloudtrail": [], "notas": []}
    causes = anomaly["root_causes"]
    rc = causes[0] if causes else {}
    service = rc.get("service", "")

    for i, c in enumerate(causes[:5], start=1):
        index[f"cad:root:{i}"] = (f"Causa raíz CAD: {c['service']} · "
                                  f"{c['usage_type'] or 'sin usage type'} · {c['region']}")

    today = dt.date.today()
    start = _date(anomaly["start"]) or today - dt.timedelta(days=1)
    end_excl = min((_date(anomaly["end"]) or start) + dt.timedelta(days=1), today)
    if end_excl <= start:
        end_excl = start + dt.timedelta(days=1)
    base_start = start - dt.timedelta(days=7)

    if service:
        flt = {"Dimensions": {"Key": "SERVICE", "Values": [service]}}
        usage_group = {"Type": "DIMENSION", "Key": "USAGE_TYPE"}
        base = _cost_by(base_start, start, flt, usage_group)
        curr = _cost_by(start, end_excl, flt, usage_group)
        ce_calls += 2
        bdays, cdays = (start - base_start).days, (end_excl - start).days
        rows = []
        for key in set(base) | set(curr):
            before, during = base.get(key, 0.0) / bdays, curr.get(key, 0.0) / cdays
            rows.append((key, before, during, during - before))
        for key, before, during, delta in sorted(rows, key=lambda r: r[3], reverse=True)[:5]:
            if abs(delta) < 0.01:
                continue
            eid = f"ce:usage:{key}"
            index[eid] = f"{key}: ${before:.2f}/día → ${during:.2f}/día ({delta:+.2f})"
            evidence["uso"].append({"id": eid, "usage_type": key,
                                    "usd_dia_antes": round(before, 2),
                                    "usd_dia_anomalia": round(during, 2)})

        tags = _cost_by(start, end_excl, flt, {"Type": "TAG", "Key": TAG_KEY})
        ce_calls += 1
        for key, usd in sorted(tags.items(), key=lambda kv: kv[1], reverse=True)[:3]:
            value = (key.split("$", 1)[1] if "$" in key else key) or "sin tag"
            eid = f"ce:tag:{value}"
            index[eid] = f"{TAG_KEY}={value}: ${usd:.2f} en la ventana"
            evidence["tags"].append({"id": eid, "valor": value, "usd": round(usd, 2)})
    else:
        evidence["notas"].append("CAD no reportó un servicio en la causa raíz.")

    source = EVENT_SOURCES.get(service)
    region = rc.get("region", "")
    region = region if "-" in region else "us-east-1"
    if rc.get("account") and account_id and rc["account"] != account_id:
        evidence["notas"].append("La anomalía es de otra cuenta; CloudTrail local no aplica "
                                 "(usar trail organizacional + Amazon Q).")
    elif source:
        evidence["cloudtrail"] = _cloudtrail(source, region, start - dt.timedelta(days=1), end_excl)
        for e in evidence["cloudtrail"]:
            index[e["id"]] = f"{e['hora']} {e['evento']} por {e['usuario'] or 'desconocido'}"
    else:
        evidence["notas"].append(f"Sin mapeo de CloudTrail para '{service}'.")

    evidence["anomalia"] = {"id": anomaly["id"], "inicio": anomaly["start"], "fin": anomaly["end"],
                            "impacto_usd": anomaly["total_impact"], "servicio": service}
    return evidence, index, ce_calls


# ---------- Explicación ----------

def _extract_json(text):
    start, end = text.find("{"), text.rfind("}")
    return json.loads(text[start:end + 1])


def explain(anomaly, evidence, index):
    usage = {"input": 0, "output": 0}
    if not MODEL_ID:
        return _fallback(evidence, index), usage
    try:
        bedrock = boto3.client("bedrock-runtime")
        payload = {"evidencia": evidence, "ids_validos": sorted(index)}
        resp = bedrock.converse(
            modelId=MODEL_ID,
            system=[{"text": SYSTEM_PROMPT}],
            messages=[{"role": "user", "content": [
                {"text": json.dumps(payload, ensure_ascii=False, default=str)}]}],
            inferenceConfig={"maxTokens": 700, "temperature": 0})
        usage = {"input": resp["usage"]["inputTokens"], "output": resp["usage"]["outputTokens"]}
        verdict = _extract_json(resp["output"]["message"]["content"][0]["text"])
    except Exception as exc:  # el demo sigue funcionando aunque Bedrock falle
        print(f"Bedrock no disponible, uso el modo determinista: {exc}")
        return _fallback(evidence, index), usage

    cited = [i for i in verdict.get("evidencia", []) if i in index]
    verdict["evidencia"] = cited  # se descarta cualquier id inventado
    if not cited:
        verdict.update(tipo="no_concluyente", confianza="baja")
    return verdict, usage


def _fallback(evidence, index):
    uso = evidence["uso"]
    project = evidence["tags"][0]["valor"] if evidence["tags"] else "sin datos"
    if uso and uso[0]["usd_dia_anomalia"] > uso[0]["usd_dia_antes"]:
        top = uso[0]
        ids = [top["id"]] + [e["id"] for e in evidence["cloudtrail"][:2]]
        return {
            "tipo": "uso",
            "causa": f"Subió el gasto en {top['usage_type']}.",
            "evidencia": ids,
            "confianza": "media" if evidence["cloudtrail"] else "baja",
            "proyecto": project,
            "accion_sugerida": "Revisar los recursos y cambios recientes del servicio afectado.",
            "faltante": "" if evidence["cloudtrail"] else "No hay cambios en CloudTrail que lo expliquen.",
        }
    return {
        "tipo": "no_concluyente",
        "causa": "La evidencia no muestra un aumento de uso claro; puede ser un cambio de tarifa o descuento.",
        "evidencia": [k for k in index if k.startswith("cad:")][:2],
        "confianza": "baja",
        "proyecto": project,
        "accion_sugerida": "Profundizar con Amazon Q desde el enlace de abajo.",
        "faltante": "Detalle de tarifas o descuentos aplicados.",
    }


# ---------- Salida ----------

def render(anomaly, verdict, index, cost):
    esc = html.escape
    rc = anomaly["root_causes"][0] if anomaly["root_causes"] else {}
    start, end = _date(anomaly["start"]), _date(anomaly["end"])
    days = max((end - start).days + 1, 1) if start and end else 1
    monthly = anomaly["total_impact"] / days * 30
    pct = f" ({float(anomaly['pct']):.0f}%)" if anomaly["pct"] not in (None, "") else ""

    lines = [
        f"<b>💸 Anomalía de costo: {esc(rc.get('service') or 'desconocido')}</b>",
        f"Impacto: <b>${anomaly['total_impact']:,.2f}</b>{pct} · ~${monthly:,.0f}/mes si continúa",
        f"Ventana: {esc(anomaly['start'])} → {esc(anomaly['end'])} · {esc(rc.get('region', ''))}",
        "",
        f"<b>Causa</b> ({esc(str(verdict.get('tipo', '')))}, confianza {esc(str(verdict.get('confianza', '')))})",
        esc(str(verdict.get("causa", ""))),
    ]
    cited = [i for i in verdict.get("evidencia", []) if i in index]
    if cited:
        lines += ["", "<b>Evidencia</b>"] + [f"• {esc(index[i])}" for i in cited]
    lines += [
        "",
        f"<b>{esc(TAG_KEY)}:</b> {esc(str(verdict.get('proyecto', '')))}",
        f"<b>Acción:</b> {esc(str(verdict.get('accion_sugerida', '')))}",
    ]
    if verdict.get("faltante"):
        lines.append(f"<i>Falta: {esc(str(verdict['faltante']))}</i>")
    if anomaly["link"]:
        lines += ["", f'🔎 <a href="{esc(anomaly["link"], quote=True)}">Profundizar con Amazon Q</a>: '
                      "abre la anomalía y pulsa <i>Investigate with Amazon Q</i>."]
    lines.append(f"<i>Costo de este análisis: ~${cost:.3f}</i>")
    return "\n".join(lines)[:4000]


def send_telegram(text):
    token = SSM.get_parameter(Name=TOKEN_PARAM, WithDecryption=True)["Parameter"]["Value"]
    data = urllib.parse.urlencode({
        "chat_id": CHAT_ID, "text": text, "parse_mode": "HTML",
        "disable_web_page_preview": "true"}).encode()
    request = urllib.request.Request(f"https://api.telegram.org/bot{token}/sendMessage", data=data)
    with urllib.request.urlopen(request, timeout=10) as resp:
        if resp.status != 200:
            raise RuntimeError(f"Telegram respondió {resp.status}")
