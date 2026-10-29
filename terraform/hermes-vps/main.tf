# ---------------------------------------------------------------------------
# Hermes VPS: one Ubuntu box that runs the always-on gateway and nothing else.
# ---------------------------------------------------------------------------
# Ownership boundary: this root provisions compute + network + first-boot
# configuration. It does NOT install Hermes (that is a reviewed, documented
# step: see the sync'd plan), does not touch R2, and does not manage anything
# inside the homelab. Keeping the boundary here means `tofu destroy` can never
# remove state the gateway is holding.
#
# Workspace-as-name: the OpenTofu workspace selects the deployment, so
# `tofu workspace new hermes-vps` yields a server called `hermes-vps` with its
# own state file under terraform.tfstate.d/hermes-vps/. The default workspace
# is refused — planning there would silently create `default`.

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

# --- 1Password-sourced material -------------------------------------------
# Ephemeral where the value is only ever handed to a provider; plain data
# source for the SSH public key and tailnet auth key because cloud-init is a
# persisted resource attribute (so the value lands in encrypted state rather
# than in the repo).

ephemeral "onepassword_item" "hcloud_token" {
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

# --- SSH key ---------------------------------------------------------------

resource "hcloud_ssh_key" "hermes" {
  name       = "${local.name}-ed25519"
  public_key = data.onepassword_item.ssh_key.public_key
  labels     = local.labels
}

# --- Firewall --------------------------------------------------------------
# Ingress is deliberately three rules wide.
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
}

# --- Server ----------------------------------------------------------------

resource "hcloud_server" "hermes" {
  name        = local.name
  server_type = var.server_type
  image       = var.image
  location    = var.location
  ssh_keys    = [hcloud_ssh_key.hermes.id]
  labels      = local.labels
  firewall_ids = [
    hcloud_firewall.hermes.id,
  ]

  public_net {
    ipv4_enabled = true
    ipv6_enabled = var.enable_ipv6
  }

  user_data = templatefile("${path.module}/cloud-init.yaml.tftpl", {
    hostname            = local.name
    hermes_user         = local.hermes_user
    hermes_home         = local.hermes_home
    hermes_os_home      = local.hermes_os_home
    ssh_public_key      = trimspace(data.onepassword_item.ssh_key.public_key)
    tailscale_authkey   = trimspace(data.onepassword_item.tailscale.credential)
    swap_size_mb        = var.swap_size_mb
    bootstrap_ssh_cidrs = var.bootstrap_ssh_cidrs
  })

  lifecycle {
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
