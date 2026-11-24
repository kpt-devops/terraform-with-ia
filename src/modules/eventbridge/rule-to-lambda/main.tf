# Regla de EventBridge (bus default) que invoca una Lambda. Desde cero: el módulo de la comunidad
# (terraform-aws-modules/eventbridge) cubre buses, pipes y schedules; para una regla y un target alcanza con dos recursos.
# El permiso para invocar la función lo da el wrapper lambda/function con allowed_triggers.
resource "aws_cloudwatch_event_rule" "this" {
  name          = var.name
  description   = var.description
  event_pattern = jsonencode(var.event_pattern)
  state         = var.enabled ? "ENABLED" : "DISABLED"
  tags          = var.tags
}

resource "aws_cloudwatch_event_target" "this" {
  rule = aws_cloudwatch_event_rule.this.name
  arn  = var.lambda_arn

  retry_policy {
    maximum_event_age_in_seconds = var.max_event_age_seconds
    maximum_retry_attempts       = var.max_retry_attempts
  }
}
