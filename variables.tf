variable "project_id" {
  description = "ID del proyecto GCP"
  type        = string
}

variable "region" {
  description = "Región de GCP"
  type        = string
  default     = "us-central1"
}

variable "bucket_name" {
  description = "Nombre del bucket para logs"
  type        = string
}

variable "topic_name" {
  description = "Nombre del tópico de Pub/Sub"
  type        = string
  default     = "logs-topic"
}

variable "receiver_function_name" {
  description = "Nombre de la función receptora HTTP"
  type        = string
  default     = "log-receiver"
}

variable "processor_function_name" {
  description = "Nombre de la función procesadora (container)"
  type        = string
  default     = "log-processor"
}

variable "logs_retention_days" {
  description = "Días de retención de logs"
  type        = number
  default     = 90
}