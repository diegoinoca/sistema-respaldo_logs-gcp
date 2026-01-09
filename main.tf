# ============================================================================
# VARIABLES LOCALES
# ============================================================================
locals {
  services_to_enable = [
    "cloudfunctions.googleapis.com",
    "run.googleapis.com",
    "pubsub.googleapis.com",
    "cloudbuild.googleapis.com",
    "artifactregistry.googleapis.com",
    "eventarc.googleapis.com",
  ]
}

# ============================================================================
# HABILITAR APIs
# ============================================================================
resource "google_project_service" "required_apis" {
  for_each = toset(local.services_to_enable)
  
  project            = var.project_id
  service            = each.value
  disable_on_destroy = false
}

# ============================================================================
# SERVICE ACCOUNTS
# ============================================================================
resource "google_service_account" "receiver_sa" {
  account_id   = "${var.receiver_function_name}-sa"
  display_name = "Service Account for log receiver"
  project      = var.project_id

  depends_on = [google_project_service.required_apis]
}

resource "google_service_account" "processor_sa" {
  account_id   = "${var.processor_function_name}-sa"
  display_name = "Service Account for log processor"
  project      = var.project_id

  depends_on = [google_project_service.required_apis]
}

# Permisos para receiver: publicar en Pub/Sub
resource "google_project_iam_member" "receiver_pubsub_publisher" {
  project = var.project_id
  role    = "roles/pubsub.publisher"
  member  = "serviceAccount:${google_service_account.receiver_sa.email}"
}

# Permisos para processor: escribir en Storage
resource "google_project_iam_member" "processor_storage_creator" {
  project = var.project_id
  role    = "roles/storage.objectCreator"
  member  = "serviceAccount:${google_service_account.processor_sa.email}"
}

resource "google_project_iam_member" "processor_pubsub_subscriber" {
  project = var.project_id
  role    = "roles/pubsub.subscriber"
  member  = "serviceAccount:${google_service_account.processor_sa.email}"
}

# ============================================================================
# CLOUD STORAGE
# ============================================================================
resource "google_storage_bucket" "logs_backup" {
  name          = var.bucket_name
  location      = var.region
  project       = var.project_id
  force_destroy = true

  uniform_bucket_level_access = true
  
  versioning {
    enabled = true
  }

  lifecycle_rule {
    condition {
      age = var.logs_retention_days
    }
    action {
      type = "Delete"
    }
  }

  lifecycle_rule {
    condition {
      age = 30
    }
    action {
      type          = "SetStorageClass"
      storage_class = "NEARLINE"
    }
  }

  depends_on = [google_project_service.required_apis]
}

# Bucket temporal para código fuente
resource "google_storage_bucket" "function_source" {
  name          = "${var.project_id}-gcf-source"
  location      = var.region
  project       = var.project_id
  force_destroy = true

  uniform_bucket_level_access = true

  depends_on = [google_project_service.required_apis]
}

# ============================================================================
# PUB/SUB
# ============================================================================
resource "google_pubsub_topic" "logs_topic" {
  name    = var.topic_name
  project = var.project_id

  depends_on = [google_project_service.required_apis]
}

resource "google_pubsub_subscription" "logs_subscription" {
  name    = "${var.topic_name}-sub"
  topic   = google_pubsub_topic.logs_topic.id
  project = var.project_id

  ack_deadline_seconds = 60
  
  message_retention_duration = "604800s"  # 7 días
  
  expiration_policy {
    ttl = ""  # Never expire
  }

  retry_policy {
    minimum_backoff = "10s"
    maximum_backoff = "600s"
  }
}

# ============================================================================
# ARTIFACT REGISTRY (Para contenedor)
# ============================================================================
resource "google_artifact_registry_repository" "functions_repo" {
  location      = var.region
  repository_id = "functions-repo"
  description   = "Repositorio Docker para Cloud Functions"
  format        = "DOCKER"
  project       = var.project_id

  depends_on = [google_project_service.required_apis]
}

# ============================================================================
# CLOUD FUNCTION 1: HTTP RECEIVER
# ============================================================================
data "archive_file" "receiver_source" {
  type        = "zip"
  source_dir  = "${path.root}/receiver-function"
  output_path = "${path.root}/.terraform/tmp/receiver-source.zip"
}

resource "google_storage_bucket_object" "receiver_source" {
  name   = "receiver-source-${data.archive_file.receiver_source.output_md5}.zip"
  bucket = google_storage_bucket.function_source.name
  source = data.archive_file.receiver_source.output_path
}

resource "google_cloudfunctions2_function" "receiver" {
  name     = var.receiver_function_name
  location = var.region
  project  = var.project_id

  description = "Función HTTP que recibe logs y los publica en Pub/Sub"

  build_config {
    runtime     = "python311"
    entry_point = "receive_log"
    
    source {
      storage_source {
        bucket = google_storage_bucket.function_source.name
        object = google_storage_bucket_object.receiver_source.name
      }
    }
  }

  service_config {
    max_instance_count    = 10
    min_instance_count    = 0
    available_memory      = "256M"
    timeout_seconds       = 60
    service_account_email = google_service_account.receiver_sa.email

    environment_variables = {
      PUBSUB_TOPIC = google_pubsub_topic.logs_topic.id
      PROJECT_ID   = var.project_id
    }

    ingress_settings = "ALLOW_ALL"
  }

  depends_on = [
    google_project_service.required_apis,
    google_project_iam_member.receiver_pubsub_publisher
  ]
}

# Permitir invocación sin autenticación (ajusta según necesites)
resource "google_cloud_run_service_iam_member" "receiver_invoker" {
  project  = var.project_id
  location = var.region
  service  = google_cloudfunctions2_function.receiver.name
  role     = "roles/run.invoker"
  member   = "allUsers"
}

# ============================================================================
# CLOUD FUNCTION 2: PROCESSOR (CONTAINER)
# ============================================================================

# Build de la imagen Docker
resource "null_resource" "build_processor_image" {
  triggers = {
    dockerfile_hash = filesha256("${path.root}/processor-function/Dockerfile")
    main_py_hash    = filesha256("${path.root}/processor-function/main.py")
    requirements    = filesha256("${path.root}/processor-function/requirements.txt")
  }

  provisioner "local-exec" {
    command = <<-EOT
      cd ${path.root}/processor-function
      gcloud builds submit \
        --tag ${var.region}-docker.pkg.dev/${var.project_id}/functions-repo/${var.processor_function_name}:latest \
        --project ${var.project_id}
    EOT
  }

  depends_on = [
    google_artifact_registry_repository.functions_repo,
    google_project_service.required_apis
  ]
}

# Cloud Function Gen2 usando contenedor
resource "google_cloudfunctions2_function" "processor" {
  name     = var.processor_function_name
  location = var.region
  project  = var.project_id

  description = "Función que procesa logs desde Pub/Sub y guarda en Storage"

  build_config {
    runtime = "python311"
    entry_point = "process_log"
    
    source {
      storage_source {
        bucket = google_storage_bucket.function_source.name
        object = google_storage_bucket_object.processor_source.name
      }
    }
    
    docker_repository = google_artifact_registry_repository.functions_repo.id
  }

  service_config {
    max_instance_count    = 10
    min_instance_count    = 0
    available_memory      = "512M"
    timeout_seconds       = 300
    service_account_email = google_service_account.processor_sa.email

    environment_variables = {
      BUCKET_NAME = google_storage_bucket.logs_backup.name
      PROJECT_ID  = var.project_id
    }

    ingress_settings = "ALLOW_INTERNAL_ONLY"
  }

  event_trigger {
    trigger_region        = var.region
    event_type            = "google.cloud.pubsub.topic.v1.messagePublished"
    pubsub_topic          = google_pubsub_topic.logs_topic.id
    retry_policy          = "RETRY_POLICY_RETRY"
    service_account_email = google_service_account.processor_sa.email
  }

  depends_on = [
    google_project_service.required_apis,
    google_project_iam_member.processor_storage_creator,
    google_project_iam_member.processor_pubsub_subscriber,
    null_resource.build_processor_image
  ]
}

# ============================================================================
# PERMISOS IAM PARA EVENTARC Y PUB/SUB
# ============================================================================

# Obtener el project number
data "google_project" "project" {
  project_id = var.project_id
}

# Permitir que el service account de la función se invoque a sí mismo
resource "google_cloud_run_service_iam_member" "processor_self_invoker" {
  project  = var.project_id
  location = var.region
  service  = google_cloudfunctions2_function.processor.name
  role     = "roles/run.invoker"
  member   = "serviceAccount:${google_service_account.processor_sa.email}"
}

# Permitir que Pub/Sub invoque la función
resource "google_cloud_run_service_iam_member" "processor_pubsub_invoker" {
  project  = var.project_id
  location = var.region
  service  = google_cloudfunctions2_function.processor.name
  role     = "roles/run.invoker"
  member   = "serviceAccount:service-${data.google_project.project.number}@gcp-sa-pubsub.iam.gserviceaccount.com"
}

# Permitir que Eventarc invoque la función
resource "google_project_iam_member" "eventarc_receiver" {
  project = var.project_id
  role    = "roles/eventarc.eventReceiver"
  member  = "serviceAccount:${google_service_account.processor_sa.email}"
}

# Dar permisos de invoker al service agent de Eventarc
resource "google_cloud_run_service_iam_member" "processor_eventarc_invoker" {
  project  = var.project_id
  location = var.region
  service  = google_cloudfunctions2_function.processor.name
  role     = "roles/run.invoker"
  member   = "serviceAccount:service-${data.google_project.project.number}@gcp-sa-eventarc.iam.gserviceaccount.com"
}

# Archivo ZIP con el código de la función processor
data "archive_file" "processor_source" {
  type        = "zip"
  source_dir  = "${path.root}/processor-function"
  output_path = "${path.root}/.terraform/tmp/processor-source.zip"
  excludes    = ["Dockerfile"]
}

resource "google_storage_bucket_object" "processor_source" {
  name   = "processor-source-${data.archive_file.processor_source.output_md5}.zip"
  bucket = google_storage_bucket.function_source.name
  source = data.archive_file.processor_source.output_path
}