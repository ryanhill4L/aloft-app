output "url" {
  value = google_cloud_run_v2_service.api.uri
}

output "image" {
  value = google_cloud_run_v2_service.api.template[0].containers[0].image
}
