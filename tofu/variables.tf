variable "project_id" {
  description = "GCP project ID to deploy into."
  type        = string

  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{4,28}[a-z0-9]$", var.project_id))
    error_message = "project_id must be a valid GCP project ID (6-30 chars, lowercase letters, digits, hyphens)."
  }
}

variable "servers" {
  description = "VPN servers to deploy, keyed by short name. Example: { fra = { zone = \"europe-west3-a\" } }."
  type = map(object({
    zone         = string
    machine_type = optional(string, "e2-micro")
  }))
  default = {}

  validation {
    condition     = alltrue([for k in keys(var.servers) : can(regex("^[a-z][a-z0-9-]{0,19}$", k))])
    error_message = "Server names must match ^[a-z][a-z0-9-]{0,19}$ (start with a lowercase letter, max 20 chars, lowercase letters/digits/hyphens)."
  }

  validation {
    condition     = alltrue([for s in values(var.servers) : can(regex("^[a-z]+-[a-z]+[0-9]+-[a-z]$", s.zone))])
    error_message = "Each server zone must look like a GCP zone, e.g. europe-west3-a or us-central1-b."
  }

  # The x86 debian-12 image and the pd-standard boot disk only work on some families.
  validation {
    condition     = alltrue([for s in values(var.servers) : can(regex("^(e2|n1|n2|n2d)-[a-z0-9-]*[a-z0-9]$", s.machine_type))])
    error_message = "Each machine_type must be in the e2, n1, n2 or n2d family (e.g. e2-micro, e2-small, n2d-standard-2)."
  }
}

variable "admin_cidrs" {
  description = "Source CIDR ranges allowed to SSH into the servers (e.g. [\"1.2.3.4/32\"])."
  type        = list(string)

  validation {
    condition     = length(var.admin_cidrs) > 0 && alltrue([for c in var.admin_cidrs : can(cidrhost(c, 0))])
    error_message = "admin_cidrs must be a non-empty list of valid CIDR ranges."
  }
}

variable "ssh_user" {
  description = "Login user created on the servers via the ssh-keys metadata."
  type        = string
  default     = "polvpn"

  validation {
    condition     = can(regex("^[a-z_][a-z0-9_-]{0,31}$", var.ssh_user))
    error_message = "ssh_user must be a valid Linux user name."
  }
}

variable "ssh_public_key_path" {
  description = "Path to the SSH public key, relative to the tofu/ directory."
  type        = string
  default     = "../.secrets/polvpn_ed25519.pub"
}

variable "wg_port" {
  description = "UDP port WireGuard listens on."
  type        = number
  default     = 51820

  validation {
    condition     = var.wg_port >= 1 && var.wg_port <= 65535 && floor(var.wg_port) == var.wg_port
    error_message = "wg_port must be an integer between 1 and 65535."
  }
}
