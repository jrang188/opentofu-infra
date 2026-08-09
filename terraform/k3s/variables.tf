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

variable "ssh_public_key_path" {
  description = "Path to the SSH public key authorized on every node. Used when ssh_public_key is unset. Must be the pair of ssh_private_key_path."
  type        = string
  default     = "~/.ssh/id_ed25519.pub"
}

variable "ssh_private_key_path" {
  description = "Path to the SSH private key OpenTofu uses to provision nodes. Used when ssh_private_key is unset. Must be the pair of ssh_public_key_path."
  type        = string
  default     = "~/.ssh/id_ed25519"
}

variable "ssh_public_key" {
  description = "SSH public key content (OpenSSH authorized_keys format) authorized on every node. Overrides ssh_public_key_path. Prefer injecting TF_VAR_ssh_public_key via the 1Password CLI (op run --env-file=.env.tofu) over writing it to a tfvars file."
  type        = string
  default     = null
}

variable "ssh_private_key" {
  description = "SSH private key content (PEM) OpenTofu uses to provision nodes. Overrides ssh_private_key_path. Prefer injecting TF_VAR_ssh_private_key via the 1Password CLI (op run --env-file=.env.tofu) over writing it to a tfvars file."
  type        = string
  default     = null
  sensitive   = true
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
