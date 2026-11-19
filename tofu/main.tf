locals {
  network_tag = "polvpn"

  ssh_public_key = trimspace(file(var.ssh_public_key_path))

  # Region is the zone with its trailing "-<letter>" removed.
  servers = {
    for name, s in var.servers : name => merge(s, {
      region = replace(s.zone, "/-[a-z]$/", "")
    })
  }
}

resource "google_project_service" "compute" {
  project            = var.project_id
  service            = "compute.googleapis.com"
  disable_on_destroy = false
}

resource "google_compute_network" "polvpn" {
  project                 = var.project_id
  name                    = "polvpn"
  auto_create_subnetworks = true

  depends_on = [google_project_service.compute]
}

resource "google_compute_firewall" "wireguard" {
  project     = var.project_id
  name        = "polvpn-allow-wireguard"
  network     = google_compute_network.polvpn.id
  direction   = "INGRESS"
  target_tags = [local.network_tag]

  source_ranges = ["0.0.0.0/0"]

  allow {
    protocol = "udp"
    ports    = [tostring(var.wg_port)]
  }
}

resource "google_compute_firewall" "ssh" {
  project     = var.project_id
  name        = "polvpn-allow-ssh-admin"
  network     = google_compute_network.polvpn.id
  direction   = "INGRESS"
  target_tags = [local.network_tag]

  source_ranges = var.admin_cidrs

  allow {
    protocol = "tcp"
    ports    = ["22"]
  }
}

resource "google_compute_firewall" "icmp" {
  project     = var.project_id
  name        = "polvpn-allow-icmp"
  network     = google_compute_network.polvpn.id
  direction   = "INGRESS"
  target_tags = [local.network_tag]

  source_ranges = ["0.0.0.0/0"]

  allow {
    protocol = "icmp"
  }
}

resource "google_compute_address" "server" {
  for_each = local.servers

  project      = var.project_id
  name         = "polvpn-${each.key}"
  region       = each.value.region
  address_type = "EXTERNAL"
  network_tier = "PREMIUM"

  labels = {
    app    = "polvpn"
    server = each.key
  }

  depends_on = [google_project_service.compute]
}

resource "google_compute_instance" "server" {
  for_each = local.servers

  project      = var.project_id
  name         = "polvpn-${each.key}"
  zone         = each.value.zone
  machine_type = each.value.machine_type

  allow_stopping_for_update = true
  tags                      = [local.network_tag]

  labels = {
    app    = "polvpn"
    server = each.key
  }

  boot_disk {
    initialize_params {
      image = "debian-cloud/debian-12"
      size  = 10
      type  = "pd-standard"
    }
  }

  network_interface {
    network = google_compute_network.polvpn.id

    access_config {
      nat_ip       = google_compute_address.server[each.key].address
      network_tier = "PREMIUM"
    }
  }

  shielded_instance_config {
    enable_secure_boot          = true
    enable_vtpm                 = true
    enable_integrity_monitoring = true
  }

  metadata = {
    ssh-keys               = "${var.ssh_user}:${local.ssh_public_key}"
    block-project-ssh-keys = "TRUE"
    enable-oslogin         = "FALSE"
  }

  depends_on = [
    google_project_service.compute,
    google_compute_firewall.ssh,
    google_compute_firewall.wireguard,
  ]
}
