variable "server_type" {
  description = <<-EOT
    Hetzner server type. cx33 (4 vCPU / 8 GB / 80 GB) is the floor: the
    gateway itself is small, but a 4 GB box leaves no headroom for the
    occasional burst and turns memory pressure into a debugging session.
  EOT
  type        = string
  default     = "cx33"

  validation {
    condition     = can(regex("^c[a-z]{0,2}[0-9]{2}$", var.server_type))
    error_message = "server_type must be a Hetzner Cloud shared-vCPU type such as cx23, cx33 or cax21."
  }
}

variable "location" {
  description = "Hetzner location. EU locations keep the CX cost-optimised pricing; latency from a Tailscale client is irrelevant for a messaging gateway."
  type        = string
  default     = "fsn1"

  validation {
    condition     = contains(["fsn1", "nbg1", "hel1"], var.location)
    error_message = "location must be one of fsn1, nbg1, hel1 (CX-series availability)."
  }
}

variable "image" {
  description = "Ubuntu Server LTS image name. Native Hermes assumes apt; do not switch this to a non-Debian image."
  type        = string
  default     = "ubuntu-24.04"
}

variable "enable_ipv6" {
  description = "Attach a public IPv6 address. Off by default: nothing needs inbound IPv6, and an unmanaged second address family is just more surface."
  type        = bool
  default     = false
}

variable "ssh_public_key" {
  description = <<-EOT
    Public key installed for the `hermes` user by cloud-init. No default: it is
    supplied by env.sh as TF_VAR_ssh_public_key. Deliberately a variable rather
    than a 1Password data source — an `onepassword_item` data source persists
    every attribute of the item, private key included, into state.
  EOT
  type        = string
  nullable    = false

  validation {
    condition     = can(regex("^ssh-(ed25519|rsa|ecdsa)[^\\n]+$", trimspace(var.ssh_public_key)))
    error_message = "ssh_public_key must be a single OpenSSH public key line (ssh-ed25519 / ssh-rsa / ssh-ecdsa)."
  }
}

variable "delete_protection" {
  description = <<-EOT
    Hetzner API-level delete protection on the server. Leave on: a destroy here
    deletes the disk holding the gateway's state. Decommissioning means turning
    this off deliberately and following the runbook, not running `tofu destroy`.
  EOT
  type        = bool
  default     = true
}

variable "bootstrap_ssh_cidrs" {
  description = <<-EOT
    Source CIDRs allowed to reach TCP/22, used only for first-boot recovery.
    Empty by default — SSH arrives over the tailnet once cloud-init has joined,
    so no public SSH is needed.

    Caveat: cloud-init runs once, and user_data is ignore_changes'd, so changing
    this variable later only updates the Hetzner firewall. The host's own ufw
    rule must be added and removed by hand (see the README's recovery section).
  EOT
  type        = list(string)
  default     = []

  validation {
    condition     = alltrue([for c in var.bootstrap_ssh_cidrs : can(cidrhost(c, 0))])
    error_message = "bootstrap_ssh_cidrs must contain valid CIDRs, e.g. 203.0.113.7/32."
  }
}

variable "swap_size_mb" {
  description = "Swapfile size in MB, created by cloud-init. Cheap insurance against a single process ballooning; not a substitute for RAM."
  type        = number
  default     = 2048

  validation {
    condition     = var.swap_size_mb >= 0 && var.swap_size_mb <= 8192
    error_message = "swap_size_mb must be between 0 (disabled) and 8192."
  }
}
