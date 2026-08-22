resource "google_iam_workload_identity_pool" "github" {
  workload_identity_pool_id = "github-pool"
  display_name              = "GitHub Actions Pool"
}

resource "google_iam_workload_identity_pool_provider" "github" {
  #checkov:skip=CKV_GCP_125:This check only recognizes conditions written against assertion.sub in exact "repo:org/repo:..." form. Our condition (below) restricts on assertion.repository instead -- a legitimate, custom-mapped claim that CKV_GCP_118 (passing) checks for. assertion.sub's exact value differs between push and pull_request events, so an exact-match sub condition would only ever authenticate one of the two triggers this pipeline needs (scan-on-PR and deploy-on-push) -- narrowing to satisfy this check would break one of them.
  workload_identity_pool_id          = google_iam_workload_identity_pool.github.workload_identity_pool_id
  workload_identity_pool_provider_id = "github-provider"

  # Required by Google as of a recent platform-wide policy change -- a
  # provider can no longer be created without an explicit condition
  # restricting which tokens it accepts. This also happens to be the
  # tighter WIF scoping flagged as optional hardening in the CI/CD notes;
  # now it's mandatory either way.
  attribute_condition = "assertion.repository == \"${var.github_user}/${var.github_repo}\""

  attribute_mapping = {
    "google.subject"       = "assertion.sub"
    "attribute.repository" = "assertion.repository"
    "attribute.ref"        = "assertion.ref"
  }

  oidc {
    issuer_uri = "https://token.actions.githubusercontent.com"
  }
}

resource "google_service_account_iam_member" "github_wif" {
  service_account_id = google_service_account.cloud_run_sa.name
  role                = "roles/iam.workloadIdentityUser"
  # Fixed: original hardcoded the pre-rename repo name "secure-cloud-ops".
  # GitHub's OIDC token asserts the CURRENT repo name ("cloudock"), so a
  # condition still checking for the old name would never match --
  # CI/CD auth would fail with a permission error that gives no hint
  # this is why.
  member = "principalSet://iam.googleapis.com/${google_iam_workload_identity_pool.github.name}/attribute.repository/${var.github_user}/${var.github_repo}"
}

# CI/CD deployer permissions for cloud-run-sa. Worth naming the tradeoff
# this makes: cloud-run-sa started as a minimal RUNTIME identity (zero
# roles, then datastore.user + one-secret access). These three roles turn
# it into the DEPLOYER identity too -- run.admin can modify/delete any
# Cloud Run service in the project, not just this one. A separate,
# dedicated CI/CD service account is the more isolated alternative if
# that blast radius ever becomes a concern; implemented as given here
# since that's what this task specifies.
resource "google_project_iam_member" "cicd_run_admin" {
  project = var.project_id
  role    = "roles/run.admin"
  member  = "serviceAccount:${google_service_account.cloud_run_sa.email}"
}

resource "google_project_iam_member" "cicd_artifact_writer" {
  project = var.project_id
  role    = "roles/artifactregistry.writer"
  member  = "serviceAccount:${google_service_account.cloud_run_sa.email}"
}

# Replaces a project-wide serviceAccountUser grant -- Checkov correctly
# flagged that as letting cloud-run-sa impersonate ANY service account in
# the project. This scopes it to only itself, which is all `gcloud run
# deploy --service-account=cloud-run-sa` actually needs.
resource "google_service_account_iam_member" "cicd_sa_user" {
  service_account_id = google_service_account.cloud_run_sa.name
  role                = "roles/iam.serviceAccountUser"
  member              = "serviceAccount:${google_service_account.cloud_run_sa.email}"
}
