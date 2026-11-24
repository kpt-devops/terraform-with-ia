variable "name" {
  description = "Nombre de la alarma."
  type        = string
}

variable "description" {
  description = "Qué significa que la alarma esté en ALARM."
  type        = string
}

variable "namespace" {
  description = "Namespace de la métrica (por ejemplo, AWS/SQS)."
  type        = string
}

variable "metric_name" {
  description = "Nombre de la métrica."
  type        = string
}

variable "dimensions" {
  description = "Dimensiones de la métrica."
  type        = map(string)
}

variable "statistic" {
  description = "Estadística: Average, Sum, Minimum, Maximum o SampleCount."
  type        = string
  default     = "Maximum"
}

variable "period" {
  description = "Periodo de evaluación en segundos."
  type        = number
  default     = 60
}

variable "evaluation_periods" {
  description = "Periodos consecutivos que deben cumplir la condición."
  type        = number
  default     = 1
}

variable "comparison_operator" {
  description = "Operador: GreaterThanThreshold, LessThanThreshold, etc."
  type        = string
  default     = "GreaterThanThreshold"
}

variable "threshold" {
  description = "Umbral."
  type        = number
}

variable "treat_missing_data" {
  description = "Cómo tratar los datos faltantes: notBreaching, breaching, ignore o missing."
  type        = string
  default     = "notBreaching"
}

variable "alarm_actions" {
  description = "ARNs a notificar al pasar a ALARM (opcional)."
  type        = list(string)
  default     = []
}

variable "ok_actions" {
  description = "ARNs a notificar al volver a OK (opcional)."
  type        = list(string)
  default     = []
}

variable "tags" {
  description = "Tags obligatorios: Project, Environment, Owner, CostCenter."
  type        = map(string)
}
