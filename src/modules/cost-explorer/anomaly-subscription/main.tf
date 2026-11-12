resource "aws_ce_anomaly_subscription" "this" {
  name             = var.name
  frequency        = var.frequency
  monitor_arn_list = var.monitor_arn_list
  tags             = var.tags

  subscriber {
    type    = "SNS"
    address = var.sns_topic_arn
  }

  threshold_expression {
    dimension {
      key           = "ANOMALY_TOTAL_IMPACT_ABSOLUTE"
      match_options = ["GREATER_THAN_OR_EQUAL"]
      values        = [tostring(var.impact_threshold_usd)]
    }
  }
}
