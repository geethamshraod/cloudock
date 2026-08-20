# Service account moved to iam.tf and consolidated there under its
# literal name (storage-writer) -- this file previously declared a
# second, differently-named SA (cloudock-storage-writer) for the same
# purpose. Only one should exist in the real project.

resource "google_storage_bucket" "security_assets" {
  name                        = "${var.project_id}-security-assets"
  location                    = var.region
  uniform_bucket_level_access = true

  versioning {
    enabled = true
  }

  lifecycle_rule {
    condition {
      age = 90
    }
    action {
      type = "Delete"
    }
  }
}

resource "google_storage_bucket_iam_member" "storage_writer_binding" {
  bucket = google_storage_bucket.security_assets.name
  role   = "roles/storage.objectCreator"
  member = "serviceAccount:${google_service_account.storage_sa.email}"
}
