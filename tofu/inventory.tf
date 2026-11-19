locals {
  inventory = {
    all = {
      children = {
        vpn = {
          hosts = {
            for name, s in local.servers : name => {
              ansible_host = google_compute_address.server[name].address
              ansible_user = var.ssh_user
              # Pin the SSH host key per instance, not per IP: a replaced VM can keep
              # its static IP but has new host keys. Added on top of ansible.cfg's ssh_args.
              ansible_ssh_common_args = "-o HostKeyAlias=polvpn-${name}-${google_compute_instance.server[name].instance_id}"
              gcp_zone                = s.zone
              gcp_instance_id         = google_compute_instance.server[name].instance_id
              wg_port                 = var.wg_port
            }
          }
        }
      }
    }
  }
}

resource "local_file" "ansible_inventory" {
  filename        = "${path.module}/../ansible/inventory/hosts.yml"
  file_permission = "0644"
  content         = "# Managed by Terraform (polvpn). Do not edit by hand.\n${yamlencode(local.inventory)}"
}
