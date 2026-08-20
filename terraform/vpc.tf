resource "google_compute_network" "vpc" {
  name                    = "cloudock-vpc"
  auto_create_subnetworks = false
}

resource "google_compute_subnetwork" "public" {
  name          = "cloudock-public-subnet"
  ip_cidr_range = "10.0.1.0/24"
  region        = var.region
  network       = google_compute_network.vpc.id
}

resource "google_compute_subnetwork" "private" {
  name          = "cloudock-private-subnet"
  ip_cidr_range = "10.0.2.0/24"
  region        = var.region
  network       = google_compute_network.vpc.id
}

resource "google_compute_firewall" "allow_ssh" {
  name          = "cloudock-allow-ssh"
  network       = google_compute_network.vpc.name
  direction     = "INGRESS"
  source_ranges = ["${var.management_ip}/32"]
  target_tags   = ["ssh-access"]

  allow {
    protocol = "tcp"
    ports    = ["22"]
  }
}

# Not in the original 7-resource list -- without this, gcloud/Terraform-driven
# SSH to a no-external-IP instance fails the same way it did back in M1,
# since Google's IAP tunnel range needs its own explicit allow.
resource "google_compute_firewall" "allow_iap_ssh" {
  name          = "cloudock-allow-iap-ssh"
  network       = google_compute_network.vpc.name
  direction     = "INGRESS"
  source_ranges = ["35.235.240.0/20"]
  target_tags   = ["ssh-access"]

  allow {
    protocol = "tcp"
    ports    = ["22"]
  }
}

resource "google_compute_firewall" "allow_https" {
  name          = "cloudock-allow-https"
  network       = google_compute_network.vpc.name
  direction     = "INGRESS"
  source_ranges = ["0.0.0.0/0"]

  allow {
    protocol = "tcp"
    ports    = ["443", "80"]
  }
}

# Not in the original 7-resource list -- the load balancer's health check
# (compute.tf) originates from Google's fixed LB/health-check ranges, not
# from the public internet generally. Same gap that broke M2's health
# check the first time around.
resource "google_compute_firewall" "allow_lb_health_check" {
  name          = "cloudock-allow-lb-health-check"
  network       = google_compute_network.vpc.name
  direction     = "INGRESS"
  source_ranges = ["130.211.0.0/22", "35.191.0.0/16"]
  target_tags   = ["web-server"]

  allow {
    protocol = "tcp"
    ports    = ["80"]
  }
}

resource "google_compute_firewall" "deny_all" {
  name          = "cloudock-deny-all-ingress"
  network       = google_compute_network.vpc.name
  direction     = "INGRESS"
  priority      = 65534
  source_ranges = ["0.0.0.0/0"]

  deny {
    protocol = "all"
  }
}

resource "google_compute_router" "nat_router" {
  name    = "cloudock-nat-router"
  network = google_compute_network.vpc.id
  region  = var.region
}

resource "google_compute_router_nat" "nat" {
  name                               = "cloudock-nat-gateway"
  router                             = google_compute_router.nat_router.name
  region                             = var.region
  nat_ip_allocate_option             = "AUTO_ONLY"
  source_subnetwork_ip_ranges_to_nat = "ALL_SUBNETWORKS_ALL_IP_RANGES"
}
