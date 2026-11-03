variable "project" {
  description = "GCP project id."
  type        = string
}

variable "region" {
  description = "Cloud Run and Artifact Registry region. us-east4 is the closest to Neon's aws-us-east-1."
  type        = string
  default     = "us-east4"
}

variable "neon_auth_url" {
  description = "Neon Auth URL for the main branch. Public by design."
  type        = string
}

variable "database_url" {
  description = "Pooled connection string for the Neon main branch."
  type        = string
  sensitive   = true
  ephemeral   = true
}

variable "database_url_version" {
  description = "Bump to write a new database_url. The URL is write-only, so Terraform cannot see it change."
  type        = number
  default     = 1
}
