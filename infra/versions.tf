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
  }
}

provider "google" {
  project = var.project
  region  = var.region
}

data "google_client_config" "current" {}
