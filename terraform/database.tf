resource "google_firestore_database" "default" {
  name = "(default)"
  # Corrected from the task's us-central1 -- the real Firestore database
  # was created in asia-southeast1 during the M4 crash-loop fix, and
  # Firestore location is permanent once set. This resource must be
  # imported, never freshly applied -- a project can only ever have one
  # default database.
  location_id = "asia-southeast1"
  type        = "FIRESTORE_NATIVE"
}
