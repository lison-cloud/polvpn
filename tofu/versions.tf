terraform {
  # Tested with OpenTofu 1.13.9 (the version pinned in tools/Dockerfile).
  required_version = "~> 1.13"

  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 8.12"
    }
    local = {
      source  = "hashicorp/local"
      version = "~> 2.9"
    }
  }
}

provider "google" {
  project = var.project_id
}
