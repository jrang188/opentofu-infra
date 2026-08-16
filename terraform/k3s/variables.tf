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

# hcloud_token, ssh_public_key, ssh_private_key, and tailscale_auth_key are no
# longer variables — they're sourced directly from 1Password via
# onepassword_item data/ephemeral resources in onepassword.tf. See that file
# for why some are ephemeral and some are plain data sources.

variable "onepassword_service_account_token_revision" {
  description = <<-EOT
    Manually-bumped revision counter for the ESO bootstrap token written by
    `kubernetes_secret_v1.onepassword_token` in secrets.tf. The token itself
    comes from `ephemeral.onepassword_item.eso_service_account_token`
    (onepassword.tf) via the provider's write-only `data_wo` attribute, so it
    is never stored in the state file — but that also means OpenTofu can no
    longer auto-derive a change-detecting revision from the token's content
    (an ephemeral value stays ephemeral through function calls, so it can't
    feed this plain argument). Bump this by 1 whenever the 1Password item's
    token value is rotated, so `data_wo` is re-pushed on the next apply.
  EOT
  type        = number
  default     = 1
  nullable    = false
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
