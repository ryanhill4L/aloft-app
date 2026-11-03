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

# The docker CLI, not the kreuzwerker provider: its build hung on handing over the context.
resource "terraform_data" "api_image" {
  triggers_replace = [sha1(join("", [for f in sort(fileset(local.backend, "**")) : filesha1("${local.backend}/${f}") if f != ".env"]))]

  provisioner "local-exec" {
    working_dir = local.backend
    environment = {
      TOKEN    = data.google_client_config.current.access_token
      REGISTRY = local.registry
      IMAGE    = "${local.image}:latest"
    }
    command = "printf %s \"$TOKEN\" | docker login -u oauth2accesstoken --password-stdin \"$REGISTRY\" && docker buildx build --platform linux/amd64 --push -t \"$IMAGE\" ."
  }
}

data "google_artifact_registry_docker_image" "api" {
  location      = var.region
  repository_id = google_artifact_registry_repository.aloft.repository_id
  image_name    = "api:latest"
  depends_on    = [terraform_data.api_image]
}

# Created by hand with gcloud (see README.md), so the value never passes through Terraform.
data "google_secret_manager_secret" "database_url" {
  secret_id = "database-url"
}

resource "google_service_account" "api" {
  account_id   = "aloft-api"
  display_name = "Aloft API"
  depends_on   = [google_project_service.apis]
}

resource "google_secret_manager_secret_iam_member" "api_database_url" {
  secret_id = data.google_secret_manager_secret.database_url.secret_id
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
      image = data.google_artifact_registry_docker_image.api.self_link
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
            secret  = data.google_secret_manager_secret.database_url.secret_id
            version = "latest"
          }
        }
      }
      startup_probe {
        http_get {
          path = "/health"
        }
      }
    }
  }

  depends_on = [
    google_project_service.apis,
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
