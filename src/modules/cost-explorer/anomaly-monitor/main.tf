resource "aws_ce_anomaly_monitor" "this" {
  name              = var.name
  monitor_type      = "DIMENSIONAL"
  monitor_dimension = var.monitor_dimension
  tags              = var.tags
}
