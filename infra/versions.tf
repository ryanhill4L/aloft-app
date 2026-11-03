terraform {
  required_version = ">= 1.10"

  # Partial config: the bucket comes from backend.hcl, which git ignores. See README.md.
  backend "gcs" {
    prefix = "aloft"
  }

  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 8.0"
    }
    docker = {
      source  = "kreuzwerker/docker"
      version = "~> 3.9"
    }
  }
}

provider "google" {
  project = var.project
  region  = var.region
}

data "google_client_config" "current" {}

provider "docker" {
  registry_auth {
    address  = local.registry
    username = "oauth2accesstoken"
    password = data.google_client_config.current.access_token
  }
}
