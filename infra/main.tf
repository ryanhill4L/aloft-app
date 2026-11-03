locals {
  registry = "${var.region}-docker.pkg.dev"
  image    = "${local.registry}/${var.project}/${google_artifact_registry_repository.aloft.repository_id}/api"
  backend  = "${path.module}/../backend"
}

# iam is here because creating the service account calls the IAM API.
resource "google_project_service" "apis" {
  for_each           = toset(["run", "artifactregistry", "secretmanager", "iam"])
  service            = "${each.key}.googleapis.com"
  disable_on_destroy = false
}

resource "google_artifact_registry_repository" "aloft" {
  location      = var.region
  repository_id = "aloft"
  format        = "DOCKER"
  depends_on    = [google_project_service.apis]
}

resource "docker_image" "api" {
  name = "${local.image}:latest"
  build {
    context  = local.backend
    platform = "linux/amd64"
  }
  triggers = {
    source = sha1(join("", [for f in sort(fileset(local.backend, "**")) : filesha1("${local.backend}/${f}") if f != ".env"]))
  }
}

resource "docker_registry_image" "api" {
  name     = docker_image.api.name
  triggers = { image = docker_image.api.image_id }
}

resource "google_secret_manager_secret" "database_url" {
  secret_id = "database-url"
  replication {
    auto {}
  }
  depends_on = [google_project_service.apis]
}

resource "google_secret_manager_secret_version" "database_url" {
  secret                 = google_secret_manager_secret.database_url.id
  secret_data_wo         = var.database_url
  secret_data_wo_version = var.database_url_version
}

resource "google_service_account" "api" {
  account_id   = "aloft-api"
  display_name = "Aloft API"
  depends_on   = [google_project_service.apis]
}

resource "google_secret_manager_secret_iam_member" "api_database_url" {
  secret_id = google_secret_manager_secret.database_url.secret_id
  role      = "roles/secretmanager.secretAccessor"
  member    = google_service_account.api.member
}

resource "google_cloud_run_v2_service" "api" {
  name                = "aloft-api"
  location            = var.region
  ingress             = "INGRESS_TRAFFIC_ALL"
  deletion_protection = false

  template {
    service_account = google_service_account.api.email

    # Migrations run at start, so a second instance would race the first.
    scaling {
      min_instance_count = 0
      max_instance_count = 1
    }

    containers {
      image = "${local.image}@${docker_registry_image.api.sha256_digest}"
      ports {
        container_port = 9090
      }
      env {
        name  = "ADDRESS"
        value = ":9090"
      }
      env {
        name  = "NEON_AUTH_URL"
        value = var.neon_auth_url
      }
      env {
        name = "DATABASE_URL"
        value_source {
          secret_key_ref {
            secret  = google_secret_manager_secret.database_url.secret_id
            version = "latest"
          }
        }
      }
      startup_probe {
        http_get {
          path = "/healthz"
        }
      }
    }
  }

  depends_on = [
    google_project_service.apis,
    google_secret_manager_secret_version.database_url,
    google_secret_manager_secret_iam_member.api_database_url,
  ]
}

# Every RPC still needs a Neon Auth JWT; public invoke only lets the request reach the API.
resource "google_cloud_run_v2_service_iam_member" "public" {
  name     = google_cloud_run_v2_service.api.name
  location = var.region
  role     = "roles/run.invoker"
  member   = "allUsers"
}
