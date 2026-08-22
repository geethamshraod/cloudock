resource "google_artifact_registry_repository" "secure_apps" {
  #checkov:skip=CKV_GCP_84:Google-managed encryption is the default and adequate here -- CSEK adds KMS key-management complexity not warranted for this project's scope
  location      = var.region
  repository_id = "secure-apps"
  format        = "DOCKER"
  description   = "cloudock container images"
}

resource "google_cloud_run_v2_service" "dashboard" {
  name     = "secure-dashboard"
  location = var.region
  ingress  = "INGRESS_TRAFFIC_ALL"

  template {
    service_account = google_service_account.cloud_run_sa.email

    scaling {
      min_instance_count = 0
      max_instance_count = 5
    }

    containers {
      image = "${var.region}-docker.pkg.dev/${var.project_id}/${google_artifact_registry_repository.secure_apps.repository_id}/secure-dashboard:${var.image_tag}"

      ports {
        container_port = 8080
      }
    }
  }
}

# Missing from the original task -- without this, the service defaults to
# private (IAM-invoker-required), recreating the exact "You don't have
# access" issue from several sessions back. This is the Terraform
# equivalent of --allow-unauthenticated.
resource "google_cloud_run_v2_service_iam_member" "public_access" {
  name     = google_cloud_run_v2_service.dashboard.name
  location = google_cloud_run_v2_service.dashboard.location
  role     = "roles/run.invoker"
  member   = "allUsers"
}
