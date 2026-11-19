# Offline tests: the google provider is mocked (no GCP calls) and the local
# provider is mocked so no inventory file is written to ../ansible/.
#   ./polvpn shell sh -c 'cd tofu && tofu test'

mock_provider "google" {}
mock_provider "local" {}

variables {
  project_id          = "polvpn-test-123"
  admin_cidrs         = ["203.0.113.7/32"]
  ssh_public_key_path = "tests/fixtures/test_ed25519.pub"
}

run "zero_servers" {
  command = apply

  variables {
    servers = {}
  }

  assert {
    condition     = output.servers == {}
    error_message = "servers output must be empty with no servers."
  }

  assert {
    condition     = yamldecode(local_file.ansible_inventory.content) == { all = { children = { vpn = { hosts = {} } } } }
    error_message = "Inventory must contain an empty vpn group."
  }

  assert {
    condition     = endswith(local_file.ansible_inventory.filename, "/../ansible/inventory/hosts.yml")
    error_message = "Inventory written to the wrong path."
  }
}

run "two_servers" {
  command = apply

  variables {
    servers = {
      fra = { zone = "europe-west3-a" }
      us1 = { zone = "us-central1-b", machine_type = "e2-small" }
    }
    wg_port = 51999
  }

  override_resource {
    target = google_compute_address.server["fra"]
    values = { address = "34.1.2.3" }
  }

  override_resource {
    target = google_compute_address.server["us1"]
    values = { address = "35.4.5.6" }
  }

  override_resource {
    target = google_compute_instance.server["fra"]
    values = { instance_id = "1111111111111111111" }
  }

  override_resource {
    target = google_compute_instance.server["us1"]
    values = { instance_id = "2222222222222222222" }
  }

  assert {
    condition = output.servers == {
      fra = { ip = "34.1.2.3", zone = "europe-west3-a", region = "europe-west3", ssh_user = "polvpn", instance_id = "1111111111111111111" }
      us1 = { ip = "35.4.5.6", zone = "us-central1-b", region = "us-central1", ssh_user = "polvpn", instance_id = "2222222222222222222" }
    }
    error_message = "Unexpected servers output."
  }

  assert {
    condition = yamldecode(local_file.ansible_inventory.content) == {
      all = { children = { vpn = { hosts = {
        fra = {
          ansible_host            = "34.1.2.3"
          ansible_user            = "polvpn"
          ansible_ssh_common_args = "-o HostKeyAlias=polvpn-fra-1111111111111111111"
          gcp_zone                = "europe-west3-a"
          gcp_instance_id         = "1111111111111111111"
          wg_port                 = 51999
        }
        us1 = {
          ansible_host            = "35.4.5.6"
          ansible_user            = "polvpn"
          ansible_ssh_common_args = "-o HostKeyAlias=polvpn-us1-2222222222222222222"
          gcp_zone                = "us-central1-b"
          gcp_instance_id         = "2222222222222222222"
          wg_port                 = 51999
        }
      } } } }
    }
    error_message = "Unexpected inventory content."
  }

  assert {
    condition     = google_compute_instance.server["fra"].name == "polvpn-fra" && google_compute_instance.server["us1"].machine_type == "e2-small" && google_compute_instance.server["fra"].machine_type == "e2-micro"
    error_message = "Instance name or machine_type wrong."
  }

  assert {
    condition     = google_compute_address.server["us1"].region == "us-central1"
    error_message = "Address region not derived from zone."
  }

  assert {
    condition     = google_compute_instance.server["fra"].can_ip_forward != true && google_compute_instance.server["fra"].metadata["block-project-ssh-keys"] == "TRUE" && google_compute_instance.server["fra"].metadata["enable-oslogin"] == "FALSE"
    error_message = "Instance must not set can_ip_forward (org policy vmCanIpForward) and must block project keys / OS Login."
  }

  assert {
    condition     = one(google_compute_instance.server["fra"].boot_disk).initialize_params[0].type == "pd-standard" && one(google_compute_instance.server["fra"].boot_disk).initialize_params[0].size == 10
    error_message = "Boot disk must be a 10 GB pd-standard disk (free tier)."
  }

  assert {
    condition     = startswith(google_compute_instance.server["fra"].metadata["ssh-keys"], "polvpn:ssh-ed25519 ")
    error_message = "ssh-keys metadata must be '<user>:<pubkey>'."
  }

  assert {
    condition     = one(google_compute_firewall.wireguard.allow).ports == tolist(["51999"]) && google_compute_firewall.ssh.source_ranges == toset(["203.0.113.7/32"])
    error_message = "Firewall rules wrong."
  }
}

run "bad_server_key" {
  command = plan

  variables {
    servers = {
      "Bad_Name" = { zone = "europe-west3-a" }
    }
  }

  expect_failures = [var.servers]
}

run "server_key_too_long" {
  command = plan

  variables {
    servers = {
      "a123456789012345678901" = { zone = "europe-west3-a" }
    }
  }

  expect_failures = [var.servers]
}

run "bad_zone" {
  command = plan

  variables {
    servers = {
      fra = { zone = "europe-west3" }
    }
  }

  expect_failures = [var.servers]
}

run "bad_machine_family" {
  command = plan

  variables {
    servers = {
      fra = { zone = "europe-west3-a", machine_type = "t2a-standard-1" }
    }
  }

  expect_failures = [var.servers]
}
