variable "cluster_name" {
  description = "Cluster name. Used as the shared suffix on every Hetzner resource and in node names."
  type        = string
  default     = "k3s"

  validation {
    condition     = can(regex("^[a-z0-9\\-]+$", var.cluster_name))
    error_message = "cluster_name must contain only lowercase letters, numbers, and dashes."
  }

  nullable = false
}

variable "hcloud_token" {
  description = "Hetzner Cloud API token with Read & Write access (Project > Security > API Tokens). Prefer exporting TF_VAR_hcloud_token over writing this to a tfvars file."
  type        = string
  nullable    = false
  sensitive   = true
}

variable "ssh_private_key_path" {
  description = "Path to the SSH private key OpenTofu uses to provision nodes. Must be the pair of ssh_public_key_path."
  type        = string
  default     = "~/.ssh/id_ed25519"
  nullable    = false
}

variable "ssh_public_key_path" {
  description = "Path to the SSH public key authorized on every node."
  type        = string
  default     = "~/.ssh/id_ed25519.pub"
  nullable    = false
}

variable "tailscale_auth_key" {
  description = "Tailscale auth key used by nodes to join the Tailnet at boot. Must be reusable and non-ephemeral, so static control planes survive key expiry. Prefer exporting TF_VAR_tailscale_auth_key."
  type        = string
  nullable    = false
  sensitive   = true
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
