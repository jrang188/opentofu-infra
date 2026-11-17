variable "hermes_server_name" {
  description = "Name of the hermes VM. Also used as the Tailscale hostname, so it must be a valid DNS label."
  type        = string
  default     = "hermes"

  validation {
    condition     = can(regex("^[a-z0-9\\-]+$", var.hermes_server_name))
    error_message = "hermes_server_name must contain only lowercase letters, numbers, and dashes."
  }

  nullable = false
}

variable "hermes_server_type" {
  description = "Hetzner Cloud server type for the hermes VM. Bump to cx32/cx42 for more RAM if the agent proves memory-hungry."
  type        = string
  default     = "cx22"

  validation {
    condition     = can(regex("^[a-z]+[0-9]+$", var.hermes_server_type))
    error_message = "hermes_server_type must be a Hetzner Cloud server type name, such as cx22."
  }

  nullable = false
}

variable "hermes_location" {
  description = "Hetzner location, e.g. fsn1 (the cluster's location)."
  type        = string
  default     = "fsn1"

  validation {
    condition     = can(regex("^[a-z]{3}[0-9]$", var.hermes_location))
    error_message = "hermes_location must be a Hetzner Cloud location code, such as fsn1."
  }

  nullable = false
}

variable "hermes_image" {
  description = "Ubuntu image, e.g. ubuntu-24.04 (not the cluster's Leap Micro snapshot)."
  type        = string
  default     = "ubuntu-24.04"

  validation {
    condition     = length(trimspace(var.hermes_image)) > 0
    error_message = "hermes_image must not be empty."
  }

  nullable = false
}

variable "hermes_tailscale_tag" {
  description = "Tailscale tag the hermes VM advertises. Must be listed in tagOwners in the Tailnet ACL policy and must match the tag the auth key in 1Password was created with."
  type        = string
  default     = "tag:hermes"

  validation {
    condition     = can(regex("^tag:[a-z0-9\\-]+$", var.hermes_tailscale_tag))
    error_message = "hermes_tailscale_tag must be a Tailscale tag, such as tag:hermes."
  }

  nullable = false
}

variable "tailscale_magicdns_domain" {
  description = "The Tailnet's MagicDNS domain, e.g. \"tail1234.ts.net\". Found in the Tailscale admin console under DNS."
  type        = string

  validation {
    condition     = can(regex("^[a-z0-9\\-]+\\.ts\\.net$", var.tailscale_magicdns_domain))
    error_message = "tailscale_magicdns_domain must be the full MagicDNS domain, such as tail1234.ts.net."
  }

  nullable = false
}
