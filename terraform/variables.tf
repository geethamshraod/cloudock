variable "project_id" {
  type        = string
  description = "GCP Project ID"
}

variable "region" {
  type    = string
  default = "asia-southeast1"
}

variable "zone" {
  type    = string
  default = "asia-southeast1-b"
}

variable "management_ip" {
  type        = string
  description = "Your public IP for SSH access (no /32 suffix -- the firewall rule adds it)"
}

variable "ssh_public_key" {
  type        = string
  description = "SSH public key content"
}

variable "image_tag" {
  type        = string
  description = "Tag of the secure-dashboard image to deploy to Cloud Run (only v1/v2 actually exist -- not 'latest')"
  default     = "v2"
}

variable "app_config_json" {
  type        = string
  description = "JSON content for the app-config secret -- supply via terraform.tfvars (gitignored), never commit the real value"
  sensitive   = true
}

variable "notification_channel_id" {
  type        = list(string)
  description = "Monitoring notification channel IDs (create via Console/gcloud first) -- leave empty to skip notifications initially"
  default     = []
}

variable "github_user" {
  type        = string
  description = "GitHub username/org that owns the repo, for Workload Identity Federation"
}

variable "github_repo" {
  type        = string
  description = "GitHub repository name, for Workload Identity Federation -- 'cloudock' after the repo rename, not the original 'secure-cloud-ops'"
  default     = "cloudock"
}
