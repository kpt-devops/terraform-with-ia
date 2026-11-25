# Alarma de CloudWatch sobre una métrica. Implementación: terraform-aws-modules/cloudwatch//modules/metric-alarm
# (aprobado en src/modules/catalog.md). Sin acciones obligatorias: el cambio de estado también llega a EventBridge.
module "alarm" {
  # checkov:skip=CKV_TF_1: módulo del Terraform Registry fijado por versión según src/modules/catalog.md.
  source  = "terraform-aws-modules/cloudwatch/aws//modules/metric-alarm"
  version = "~> 6.0"

  alarm_name          = var.name
  alarm_description   = var.description
  namespace           = var.namespace
  metric_name         = var.metric_name
  dimensions          = var.dimensions
  statistic           = var.statistic
  period              = var.period
  evaluation_periods  = var.evaluation_periods
  comparison_operator = var.comparison_operator
  threshold           = var.threshold
  treat_missing_data  = var.treat_missing_data

  alarm_actions = var.alarm_actions
  ok_actions    = var.ok_actions

  tags = var.tags
}
