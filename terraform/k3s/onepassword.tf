# ---------------------------------------------------------------------------
# 1Password: secret sourcing
# ---------------------------------------------------------------------------
# Replaces `.env.tofu` / `op run --env-file=.env.tofu` env-var injection.
# `provider "onepassword" {}` in providers.tf is intentionally empty — it
# authenticates via the local `op` CLI session, so the machine running
# `tofu plan`/`tofu apply` must have `op` installed and signed in. Same
# category of requirement as the Tailscale login rule in AGENTS.md.
#
# Ephemeral resources (OpenTofu >= 1.10) are used only where the consuming
# argument actually accepts ephemeral values: provider "hcloud" auth
# (providers.tf) and the write-only `data_wo` Secret payload (secrets.tf).
#
# The kube-hetzner module's own input variables (hcloud_token, ssh_public_key,
# ssh_private_key, tailscale_auth_key) are NOT declared `ephemeral = true`
# upstream, and the module re-stores hcloud_token into its own hcloud-ccm/csi
# Kubernetes Secret via a plain (non-write-only) argument — so OpenTofu
# rejects an ephemeral value at that boundary outright. For those four, plain
# `onepassword_item` data sources are used instead: still no `.env.tofu` file
# and no TF_VAR_* env vars, but the value is unavoidably readable in state
# once the module re-stores it, same exposure as today's var-based flow.

locals {
  onepassword_vault = "Development"
}

# --- hcloud provider auth (ephemeral — never touches state) ----------------

ephemeral "onepassword_item" "hcloud_token" {
  vault = local.onepassword_vault
  title = "hetzner-cloud-api-token"

}

# --- kube-hetzner module inputs (plain data sources — module can't accept
#     ephemeral values here; see comment above) -----------------------------

data "onepassword_item" "hcloud_token" {
  vault = local.onepassword_vault
  title = "hetzner-cloud-api-token"
}

data "onepassword_item" "ssh_key" {
  vault = local.onepassword_vault
  title = "ssh-key"
}

data "onepassword_item" "tailscale" {
  vault = local.onepassword_vault
  title = "tailscale-auth-key"
}

# --- ESO bootstrap token (ephemeral — never touches state) -----------------
# Written to the cluster via secrets.tf's write-only `data_wo`. See that
# file for why data_wo_revision can no longer be derived from this value.

ephemeral "onepassword_item" "eso_service_account_token" {
  vault = local.onepassword_vault
  title = "eso-1password-service-account-token"
}
