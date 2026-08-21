# Referenced by the VM below but never declared in the original task list.
resource "google_service_account" "web_sa" {
  account_id   = "cloudock-web-sa"
  display_name = "Webserver VM Service Account"
}

resource "google_compute_instance" "webserver" {
  #checkov:skip=CKV_GCP_38:Google-managed disk encryption is the default and adequate here -- CSEK adds KMS key-management complexity not warranted for this project's scope
  #checkov:skip=CKV_GCP_40:Intentional -- this is the project's public web tier, meant to be reachable directly
  name                      = "cloudock-webserver"
  machine_type              = "e2-micro"
  zone                      = var.zone
  tags                      = ["web-server"]
  allow_stopping_for_update = true

  boot_disk {
    initialize_params {
      image = "debian-cloud/debian-11"
    }
  }

  network_interface {
    subnetwork = google_compute_subnetwork.public.id
    access_config {} # ephemeral external IP
  }

  metadata = {
    ssh-keys                = "user:${var.ssh_public_key}"
    block-project-ssh-keys  = "true"
  }

  shielded_instance_config {
    enable_secure_boot          = true
    enable_vtpm                 = true
    enable_integrity_monitoring = true
  }

  service_account {
    email  = google_service_account.web_sa.email
    scopes = ["cloud-platform"]
  }
}

# Not in the original list -- google_compute_backend_service can't attach
# a bare VM directly, it needs an instance group as the backend target.
resource "google_compute_instance_group" "web_ig" {
  name      = "cloudock-web-ig"
  zone      = var.zone
  instances = [google_compute_instance.webserver.id]

  named_port {
    name = "http"
    port = 80
  }
}

resource "google_compute_health_check" "http" {
  name = "cloudock-http-health-check"

  http_health_check {
    port = 80
  }
}

resource "google_compute_backend_service" "web_backend" {
  name          = "cloudock-web-backend"
  health_checks = [google_compute_health_check.http.id]
  # Added -- armor.tf creates the policy's rules, but nothing previously
  # attached it to anything. Without this line the policy exists but has
  # zero actual effect on traffic.
  security_policy = google_compute_security_policy.cloudock.id

  backend {
    group = google_compute_instance_group.web_ig.id
  }
}

resource "google_compute_url_map" "web_map" {
  name            = "cloudock-web-map"
  default_service = google_compute_backend_service.web_backend.id
}

resource "google_compute_target_http_proxy" "http_proxy" {
  name    = "cloudock-http-proxy"
  url_map = google_compute_url_map.web_map.id
}

resource "google_compute_global_forwarding_rule" "http_rule" {
  name       = "cloudock-http-rule"
  target     = google_compute_target_http_proxy.http_proxy.id
  port_range = "80"
}
