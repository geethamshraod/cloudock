resource "google_secret_manager_secret" "app_config" {
  secret_id = "app-config"

  replication {
    auto {}
  }
}

# Missing from the original task -- a secret with no version has no
# content. Same failure mode as the empty-secret crash a few sessions
# back, just via Terraform instead of a mistranslated echo command this
# time. Sourced from a variable so the real value is never committed.
resource "google_secret_manager_secret_version" "app_config_v1" {
  secret      = google_secret_manager_secret.app_config.id
  secret_data = var.app_config_json
}

resource "google_secret_manager_secret_iam_member" "cloud_run_access" {
  secret_id = google_secret_manager_secret.app_config.secret_id
  role      = "roles/secretmanager.secretAccessor"
  member    = "serviceAccount:${google_service_account.cloud_run_sa.email}"
}
