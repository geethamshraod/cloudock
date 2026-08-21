resource "google_service_account" "cloud_run_sa" {
  account_id   = "cloud-run-sa"
  display_name = "Cloud Run Service Account"
}

resource "google_project_iam_member" "firestore_access" {
  project = var.project_id
  role    = "roles/datastore.user"
  member  = "serviceAccount:${google_service_account.cloud_run_sa.email}"
}

# Sole declaration of this SA -- previously duplicated in storage.tf under
# a different name (cloudock-storage-writer). Consolidated here using the
# literal name, matching what M2 actually appears to have created.
resource "google_service_account" "storage_sa" {
  account_id   = "cloudock-storage-writer"
  display_name = "Storage Writer SA"
}
