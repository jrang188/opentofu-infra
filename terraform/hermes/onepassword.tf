# Secrets via 1Password; the provider authenticates through the local `op`
# CLI session. Ephemeral only where the consuming argument accepts it.

locals {
  onepassword_vault = "Development"
}

# --- hcloud provider auth (ephemeral — never touches state) ----------------

ephemeral "onepassword_item" "hcloud_token" {
  vault = local.onepassword_vault
  title = "hetzner-cloud-api-token"
}

# --- VM access + tailnet enrolment (plain data sources) --------------------

data "onepassword_item" "tailscale_auth_key" {
  vault = local.onepassword_vault
  title = "tailscale-auth-key-hermes"

  # Separate from the k3s "tailscale-auth-key": auth keys are bound to their
  # tags at creation and the k3s key carries tag:k8s-control-plane.
  # Requirements: reusable + non-ephemeral (ephemeral keys reap offline
  # nodes), created with tag:hermes in the Tailscale admin console, stored
  # here. The key unavoidably lands in state via user_data — same exposure
  # the k3s root accepts.
}
