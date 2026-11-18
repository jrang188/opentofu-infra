# ---------------------------------------------------------------------------
# hermes: standalone tailnet-only VM for the always-on agent daemon
# ---------------------------------------------------------------------------
# No public inbound (empty firewall rule set), no private network, no
# Kubernetes. The agent itself is installed manually; Terraform stops at
# "VM exists and is on the tailnet".

# --- Firewall: zero rules = default-deny inbound; egress is unfiltered -----

resource "hcloud_firewall" "hermes" {
  name = "${var.hermes_server_name}-tailnet-only"
}

# --- SSH key: reference the project's existing key --------------------------
# Hetzner rejects duplicate keys per project (uniqueness_error), and the k3s
# root already registered the operator's key. Look it up instead of creating
# a second copy. Update the fingerprint if the key is ever rotated.

data "hcloud_ssh_key" "hermes" {
  fingerprint = var.hermes_ssh_key_fingerprint
}

# --- The VM ----------------------------------------------------------------

resource "hcloud_server" "hermes" {
  name        = var.hermes_server_name
  server_type = var.hermes_server_type
  image       = var.hermes_image
  location    = var.hermes_location

  ssh_keys     = [data.hcloud_ssh_key.hermes.id]
  firewall_ids = [hcloud_firewall.hermes.id]

  labels = {
    provisioner = "terraform"
    role        = "hermes"
  }

  # cloud-init: install tailscale and enrol in the tailnet on first boot.
  # Via install.sh, NOT the distro package: on Ubuntu 26.04 that is the
  # confined snap, whose tailscaled cannot run Tailscale SSH as root
  # ("operation not permitted").
  # --ssh = Tailscale SSH; --accept-dns=true = MagicDNS on (fine here — no
  # k3s etcd constraint like the cluster nodes).
  user_data = <<-EOT
    #cloud-config
    package_update: true
    runcmd:
      - curl -fsSL https://tailscale.com/install.sh | sh
      - >-
        tailscale up
        --auth-key=${data.onepassword_item.tailscale_auth_key.credential}
        --hostname=${var.hermes_server_name}
        --advertise-tags=${var.hermes_tailscale_tag}
        --ssh
        --accept-dns=true
    EOT

  # TODO: set `delete_protection = true` once the agent install and its data
  # live on this box; unprotected until then. No private network either — a
  # tailnet-only standalone VM doesn't need one, and adding one would force
  # a server rebuild.
}

# Firewall attached via `firewall_ids` (a separate hcloud_firewall_attachment
# would double-attach the same firewall).
