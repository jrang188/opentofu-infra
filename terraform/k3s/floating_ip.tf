# ---------------------------------------------------------------------------
# Ingress floating IP — deliberately NOT the module's nodepool `floating_ip`
# ---------------------------------------------------------------------------
# kube-hetzner's `floating_ip` nodepool attribute is an *egress* primitive. Its
# only documented use (module docs/llms.md) is an "egress" agent nodepool paired
# with Cilium's Egress Gateway, where the whole point is that traffic *leaves*
# via the floating IP. For that job the module is right to make the floating IP
# the node's network identity, which it does by emitting, on exactly the node
# that carries it (module control_planes.tf, `k3s-config`):
#
#     node-external-ip    = <floating ip>
#     flannel-external-ip = true
#
# Both are wrong for an ingress VIP, and the second one is a cluster-wide
# outage waiting for a trigger:
#
#   * `flannel-external-ip` makes flannel publish the Node's ExternalIP as its
#     VXLAN endpoint. Peers would then target the floating IP — but every
#     flannel.1 in this cluster is bound `dev eth1 local 10.255.0.x`, so the
#     outer packets get forced out the private NIC with an RFC1918 source and
#     black-hole. The home agent (`flannel-iface: tailscale0`, see
#     docs/homelab-ecosystem.md) has no path to a public address at all. This
#     is latent rather than live only because the Hetzner CCM never sets an
#     ExternalIP on these nodes (issue #1), so flannel silently falls back to
#     the internal IP — which means *fixing issue #1 would detonate it*.
#   * `node-external-ip` pins one control plane's external address to an IP
#     that is not that server's own, which is the opposite of what issue #1's
#     root fix needs, and it cannot be overridden per-node.
#
# Owning the floating IP here instead keeps the module's
# `control_plane_external_ipv4_by_node` empty, so neither flag is ever emitted.
# See docs/adr/ for the full decision record.

locals {
  # The control-plane node slot that carries the ingress address. Matches the
  # `nodes` map key in kube.tf; the module composes state keys as
  # "<pool index>-<node key>-<pool name>".
  ingress_node_key = "0-0-control-plane"
}

resource "hcloud_floating_ip" "ingress" {
  type = "ipv4"

  # Must match the control-plane nodepool location in kube.tf — a floating IP
  # can only be assigned to a server in its home location.
  home_location = "fsn1"

  # Same labels the module put on this resource while it owned it, so the plan
  # after the state migration is a clean no-op and the address stays findable
  # by the `cluster=<name>` selector.
  labels = {
    cluster     = var.cluster_name
    engine      = "k3s"
    provisioner = "terraform"
  }

  # This address is what homelab-k8s's external-dns points real domains at
  # (jrang188/homelab-k8s#9). Losing it means re-pointing every record, so
  # refuse the delete at the API. Deliberately not `prevent_destroy`, which
  # would break the documented teardown flow in README.md; flip this to false
  # in a separate apply when you genuinely intend to tear the cluster down.
  delete_protection = true
}

resource "hcloud_floating_ip_assignment" "ingress" {
  floating_ip_id = hcloud_floating_ip.ingress.id
  server_id      = module.kube-hetzner.control_planes[local.ingress_node_key].id
}

# ---------------------------------------------------------------------------
# On-node binding
# ---------------------------------------------------------------------------
# Hetzner routes the floating IP to the assigned server but does not configure
# it there — the OS has to own the address or it answers nothing.
#
# The module did this with a one-shot `remote-exec` whose `triggers_replace` is
# only the server id and the floating IP id, so nothing ever re-asserts it. The
# address lives in /etc/NetworkManager/system-connections/cloud-init-eth0.nmconnection,
# a file cloud-init owns and may re-render on boot — and with
# `automatically_upgrade_os = true` these nodes reboot unattended via kured.
# A systemd oneshot that re-checks on every boot closes that gap.
locals {
  ingress_floating_ip_script = <<-EOT
    #!/bin/sh
    set -eu

    FIP="${hcloud_floating_ip.ingress.ip_address}"
    NODE_IP="${module.kube-hetzner.control_planes[local.ingress_node_key].ipv4_address}"

    # Public interface = whichever device holds the route to Hetzner's
    # link-local gateway. Same detection the module uses, so the two agree.
    ETH=$(ip -4 route get 172.31.1.1 2>/dev/null | awk '{for(i=1;i<=NF;i++) if($i=="dev"){print $(i+1); exit}}')
    if [ -z "$ETH" ]; then
        echo "kh-ingress-floating-ip: could not detect public interface" >&2
        exit 1
    fi

    # Happy path must be a no-op. Reactivating the connection bounces the
    # public NIC, and the Tailscale session this node is managed over rides on
    # it — so only touch NetworkManager when the address is actually missing.
    if ip -4 addr show dev "$ETH" | grep -q "inet $FIP/32"; then
        exit 0
    fi

    CONN=$(nmcli -g GENERAL.CONNECTION device show "$ETH" 2>/dev/null | head -1)
    if [ -z "$CONN" ]; then
        echo "kh-ingress-floating-ip: no NetworkManager connection for $ETH" >&2
        exit 1
    fi

    echo "kh-ingress-floating-ip: $FIP missing on $ETH, re-asserting via $CONN"

    # Set the full manual config rather than appending the floating IP, so this
    # also repairs a profile that cloud-init reset to DHCP.
    nmcli connection modify "$CONN" \
        ipv4.method manual \
        ipv4.addresses "$FIP/32,$NODE_IP/32" gw4 172.31.1.1 \
        ipv4.route-metric 100
    nmcli connection up "$CONN"
  EOT

  ingress_floating_ip_unit = <<-EOT
    [Unit]
    Description=Bind the ingress floating IP to the public interface
    After=NetworkManager.service network-online.target
    Wants=network-online.target

    [Service]
    Type=oneshot
    ExecStart=/usr/local/bin/kh-ingress-floating-ip.sh
    RemainAfterExit=true

    [Install]
    WantedBy=multi-user.target
  EOT
}

# Installed over SSH rather than through the nodepool's `extra_write_files`,
# because the module sets `ignore_changes = [user_data]` on the server resource
# (modules/host/main.tf) — a cloud-init change would silently never reach the
# running node, which is the same trap hit in issue #3. Keying
# `triggers_replace` on the server id means a replaced node gets it too.
resource "terraform_data" "ingress_floating_ip_binding" {
  triggers_replace = {
    server_id  = module.kube-hetzner.control_planes[local.ingress_node_key].id
    ip_address = hcloud_floating_ip.ingress.ip_address
    script     = sha1(local.ingress_floating_ip_script)
    unit       = sha1(local.ingress_floating_ip_unit)
  }

  # Over the Tailnet: public SSH is closed (firewall_ssh_source = null), so the
  # machine running apply must be logged in to the Tailnet — same requirement
  # AGENTS.md states for the module itself.
  connection {
    type        = "ssh"
    user        = "root"
    host        = module.kube-hetzner.tailscale_control_plane_magicdns_hosts[local.ingress_node_key]
    private_key = data.onepassword_item.ssh_key.private_key
  }

  provisioner "file" {
    content     = local.ingress_floating_ip_script
    destination = "/usr/local/bin/kh-ingress-floating-ip.sh"
  }

  provisioner "file" {
    content     = local.ingress_floating_ip_unit
    destination = "/etc/systemd/system/kh-ingress-floating-ip.service"
  }

  provisioner "remote-exec" {
    inline = [
      "chmod 0755 /usr/local/bin/kh-ingress-floating-ip.sh",
      "systemctl daemon-reload",
      "systemctl enable --now kh-ingress-floating-ip.service",
    ]
  }

  depends_on = [hcloud_floating_ip_assignment.ingress]
}
