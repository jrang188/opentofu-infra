# ---------------------------------------------------------------------------
# Hermes VPS: one Ubuntu box that runs the always-on gateway and nothing else.
# ---------------------------------------------------------------------------
# Ownership boundary: this root provisions compute + network + first boot. It
# does NOT install Hermes, and does not touch R2 or the homelab. That keeps
# *code* from changing the running agent's runtime.
#
# It does NOT make `tofu destroy` harmless: destroying this root deletes the
# server and therefore the disk holding HERMES_HOME. Two explicit protections
# stand in the way, and both must be removed deliberately before a teardown can
# happen:
#   1. lifecycle.prevent_destroy on the server and the firewall
#   2. delete_protection on the server, enforced by the Hetzner API
# Decommissioning is a reviewed sequence, not a `destroy` away.
#
# Workspace-as-name: the OpenTofu workspace selects the deployment, so
# `tofu workspace new hermes-vps` yields a server called `hermes-vps` with its
# own state file under terraform.tfstate.d/hermes-vps/. The default workspace is
# refused — planning there would silently create `default`.

locals {
  onepassword_vault = "Development"

  name = terraform.workspace

  # Architecture constants, not knobs. HERMES_HOME and HOME are preserved from
  # the container layout on purpose: thousands of absolute /opt/data/... paths
  # in skills, scripts and cron prompts resolve correctly only if the host
  # matches. See the plan's "path preservation" section before changing these.
  hermes_user    = "hermes"
  hermes_home    = "/opt/data"
  hermes_os_home = "/opt/data/home"

  labels = {
    managed-by = "opentofu"
    root       = "terraform-hermes-vps"
    workspace  = terraform.workspace
  }
}

# --- Encryption guard ------------------------------------------------------
# State encryption is configured through TF_ENCRYPTION (see terraform.tf). The
# environment form is what keeps `tofu init`/`validate` secret-free, but it also
# means a fresh workspace would write *plaintext* state if the operator forgot
# to source env.sh. This guard closes that hole for apply: it runs before
# anything else and aborts if the variable is missing.
#
# Residual gap, stated rather than hidden: `tofu plan -out=FILE` with no
# TF_ENCRYPTION still produces an unencrypted plan file. Don't pass -out
# without sourcing env.sh; plan files are gitignored but not secret-safe.

resource "terraform_data" "encryption_guard" {
  # Replace every run so the provisioner executes on each apply, not only on
  # first creation.
  triggers_replace = timestamp()

  provisioner "local-exec" {
    command = <<-EOT
      if [ -z "$${TF_ENCRYPTION:-}" ]; then
        echo "ERROR: TF_ENCRYPTION is not set — state would be written unencrypted." >&2
        echo "       Run: source terraform/hermes-vps/env.sh" >&2
        exit 1
      fi
    EOT
  }
}

# --- 1Password-sourced material -------------------------------------------
# Ephemeral where the value is only ever handed to a provider. The SSH public
# key is NOT read through a data source on purpose: `onepassword_item` data
# sources persist every attribute of the item — including its private key —
# into state. A public key is not a secret, so env.sh passes it as TF_VAR
# instead. The tailnet enrollment key does have to reach cloud-init, so it is
# unavoidably in (encrypted) state and in user_data; see the README.

ephemeral "onepassword_item" "hcloud_token" {
  vault = local.onepassword_vault
  title = "hetzner-cloud-api-token"
}

data "onepassword_item" "tailscale" {
  vault = local.onepassword_vault
  title = "tailscale-auth-key"
}

# --- Firewall --------------------------------------------------------------
# Ingress is deliberately two rules wide, plus an opt-in third.
#
# Note on tailnet SSH: a Tailscale SSH/SCP connection does not arrive as
# inbound TCP/22 on eth0 — it arrives as WireGuard UDP on 41641. Allowing
# TCP/22 does nothing for tailnet access; allowing UDP/41641 is what gives the
# tailnet a direct path (otherwise everything relays through DERP, which works
# but is slower and depends on Tailscale infrastructure).

resource "hcloud_firewall" "hermes" {
  name   = "${local.name}-fw"
  labels = local.labels

  rule {
    description = "ICMP echo for diagnostics"
    direction   = "in"
    protocol    = "icmp"
    source_ips  = ["0.0.0.0/0"]
  }

  rule {
    description = "Tailscale direct path (WireGuard)"
    direction   = "in"
    protocol    = "udp"
    port        = "41641"
    source_ips  = ["0.0.0.0/0"]
  }

  dynamic "rule" {
    for_each = length(var.bootstrap_ssh_cidrs) > 0 ? [1] : []
    content {
      description = "TEMPORARY bootstrap SSH — remove bootstrap_ssh_cidrs after the tailnet join is verified"
      direction   = "in"
      protocol    = "tcp"
      port        = "22"
      source_ips  = var.bootstrap_ssh_cidrs
    }
  }

  lifecycle {
    # Removing the management network is part of a decommission, not a side
    # effect of an unrelated change.
    prevent_destroy = true
  }
}

# --- Server ----------------------------------------------------------------

resource "hcloud_server" "hermes" {
  name        = local.name
  server_type = var.server_type
  image       = var.image
  location    = var.location
  labels      = local.labels
  firewall_ids = [
    hcloud_firewall.hermes.id,
  ]

  # API-level protection: a delete call fails until this is turned off
  # deliberately. Belt to lifecycle.prevent_destroy's braces.
  delete_protection = var.delete_protection

  # No project SSH key is attached. Creating one would collide with any key
  # already registered in the project (Hetzner enforces fingerprint
  # uniqueness) and would tie this root's lifecycle to a shared object. The
  # public key is installed for the `hermes` user by cloud-init instead; the
  # console/rescue path is documented in the README.

  public_net {
    ipv4_enabled = true
    ipv6_enabled = var.enable_ipv6
  }

  user_data = templatefile("${path.module}/cloud-init.yaml.tftpl", {
    hostname            = local.name
    hermes_user         = local.hermes_user
    hermes_home         = local.hermes_home
    hermes_os_home      = local.hermes_os_home
    ssh_public_key      = trimspace(var.ssh_public_key)
    tailscale_authkey   = trimspace(data.onepassword_item.tailscale.credential)
    swap_size_mb        = var.swap_size_mb
    bootstrap_ssh_cidrs = var.bootstrap_ssh_cidrs
  })

  depends_on = [terraform_data.encryption_guard]

  lifecycle {
    # Destroying this resource removes the disk holding HERMES_HOME. Make that
    # a deliberate two-step: remove this block, follow the decommission
    # runbook, then destroy.
    prevent_destroy = true

    # The default workspace is not a deployment target: it would create a
    # server named "default" whose state nobody accounts for.
    precondition {
      condition     = terraform.workspace != "default"
      error_message = "Refusing to deploy in the default workspace. Run: tofu workspace new hermes-vps"
    }

    # cloud-init only runs on first boot, so a template edit would otherwise
    # plan a destroy/recreate of a server that holds live state. Bootstrap
    # changes are applied to the running host by hand and recorded in the
    # runbook; recreating the VPS is a decision, not a side effect.
    ignore_changes = [user_data]
  }
}
