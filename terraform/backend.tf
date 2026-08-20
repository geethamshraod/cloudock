# NOTE: backend blocks cannot reference variables -- this bucket name must
# be a literal string. Create it once, before "terraform init":
#   gsutil mb -b on -l asia-southeast1 gs://cloudock-503009-tfstate
#   gsutil versioning set on gs://cloudock-503009-tfstate
terraform {
  backend "gcs" {
    bucket = "cloudock-503009-tfstate"
    prefix = "cloudock"
  }
}
