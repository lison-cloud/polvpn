output "servers" {
  description = "Deployed VPN servers: name => { ip, zone, region, ssh_user, instance_id }."
  value = {
    for name, s in local.servers : name => {
      ip          = google_compute_address.server[name].address
      zone        = s.zone
      region      = s.region
      ssh_user    = var.ssh_user
      instance_id = google_compute_instance.server[name].instance_id
    }
  }
}
