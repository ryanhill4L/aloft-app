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
