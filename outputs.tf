output "receiver_url" {
  description = "URL para enviar logs (HTTP endpoint)"
  value       = google_cloudfunctions2_function.receiver.service_config[0].uri
}

output "bucket_name" {
  description = "Nombre del bucket de logs"
  value       = google_storage_bucket.logs_backup.name
}

output "pubsub_topic" {
  description = "Nombre del tópico Pub/Sub"
  value       = google_pubsub_topic.logs_topic.name
}

output "test_command" {
  description = "Comando para probar el sistema"
  value       = <<-EOT
    curl -X POST ${google_cloudfunctions2_function.receiver.service_config[0].uri} \
      -H "Content-Type: application/json" \
      -d '{
        "level": "INFO",
        "message": "Test log message",
        "timestamp": "'$(date -u +%Y-%m-%dT%H:%M:%SZ)'",
        "source": "test-app"
      }'
  EOT
}

output "view_logs_command" {
  description = "Comando para ver logs respaldados"
  value       = "gsutil ls -r gs://${google_storage_bucket.logs_backup.name}/logs/"
}