module "kube-hetzner" {
  source  = "kube-hetzner/kube-hetzner/hcloud"
  version = ">= 3.0.1, < 4.0.0"

  providers = {
    hcloud = hcloud
  }

  # See onepassword.tf: these are plain (non-ephemeral) data sources, not the
  # ephemeral resources used for provider auth — this module's input
  # variables aren't declared `ephemeral = true` upstream, so OpenTofu
  # rejects an ephemeral value here.
  hcloud_token   = data.onepassword_item.hcloud_token.credential
  cluster_name   = var.cluster_name
  network_region = "eu-central"

  ssh_public_key  = data.onepassword_item.ssh_key.public_key
  ssh_private_key = data.onepassword_item.ssh_key.private_key

  # ---------------------------------------------------------------------------
  # Node transport: Tailscale
  # ---------------------------------------------------------------------------
  # Closes the public Kubernetes API and SSH entirely. Terraform, kubectl and SSH
  # all reach the nodes over the Tailnet, so the machine running `tofu apply`
  # must be logged in to the same Tailnet.
  #
  # This secures the MANAGEMENT plane only. Public app ingress on :80/:443 is a
  # separate path and is unaffected — see the ingress section below.
  #
  # bootstrap_mode = "cloud_init" is required here: with firewall_ssh_source = null
  # there is no public SSH for the default "remote_exec" bootstrap to use, so
  # Tailscale has to come up from cloud-init before Terraform ever connects.
  node_transport_mode = "tailscale"
  tailscale_auth_key  = data.onepassword_item.tailscale.credential

  tailscale_node_transport = {
    bootstrap_mode  = "cloud_init"
    magicdns_domain = var.tailscale_magicdns_domain

    auth = {
      mode = "auth_key"
      # Tag naming convention (shared with ../../../homelab-nix): tag:k8s-<role>
      # or tag:k8s-<role>-<location>. Requires tag:k8s-control-plane to be owned
      # in the Tailnet ACL's tagOwners before this applies cleanly.
      advertise_tags_control_plane = ["tag:k8s-control-plane"]
    }

    routing = {
      # Each control plane advertises its own private /32 over Tailscale so
      # Tailscale-only nodes (e.g. a home k3s agent with no Hetzner private
      # network presence) have a route back to flannel's node-ips. Reboot-safe:
      # a control plane's /32 drops with it during rolling upgrades while the
      # others keep advertising theirs. Requires one-time manual approval of
      # the advertised routes in the Tailscale admin console.
      # See ../../../homelab-nix/docs/adr/0001-tailscale-subnet-routes-for-home-agent-pod-network.md
      advertise_node_private_routes = true
    }
  }

  # null = no public firewall rule at all. The module rejects world-open values
  # in Tailscale mode; access comes from the Tailnet instead.
  firewall_kube_api_source = null
  firewall_ssh_source      = null

  # ---------------------------------------------------------------------------
  # Topology: 3 control planes, workloads scheduled on them, no agent nodes
  # ---------------------------------------------------------------------------
  # 3 gives etcd quorum and must stay an odd number. All in one location for the
  # lowest etcd latency, at the cost of no datacenter-failure resilience.
  control_plane_nodepools = [
    {
      name        = "control-plane"
      server_type = "cx23"
      location    = "fsn1"
      labels      = []
      taints      = []
      # Explicit `nodes` map instead of `count = 3`, so exactly one node can
      # carry `floating_ip = true` (nodepool-level floating_ip applies to
      # every node in the pool — one floating IP per node — which is not
      # what a single stable ingress address needs). The composite state key
      # this produces per node ("0-<n>-control-plane") is identical to what
      # `count = 3` produces, so this is not a topology change: it does not
      # replace the existing nodes (kube-hetzner locals.tf
      # control_plane_nodes_from_maps_for_counts vs.
      # control_plane_nodes_from_integer_counts).
      nodes = {
        "0" = {
          # Stable public IPv4 that homelab-k8s's external-dns targets
          # instead of any one node's own address, so DNS survives node
          # replacement. See jrang188/homelab-k8s#9.
          floating_ip = true
        }
        "1" = {}
        "2" = {}
      }
      # kube-hetzner hardcodes --accept-dns=false in the Tailscale bootstrap
      # script (locals.tf), but k3s etcd peer TLS requires MagicDNS for
      # hostname verification between control planes. This systemd unit
      # re-enables DNS acceptance on every boot, not just cloud-init's first
      # run — see docs/runbooks/tailscale-private-route-advertisement.md.
      extra_write_files = [
        {
          path        = "/etc/systemd/system/tailscale-accept-dns.service"
          owner       = "root:root"
          permissions = "0644"
          content     = <<-EOT
            [Unit]
            Description=Re-enable Tailscale MagicDNS for k3s etcd peer TLS
            After=tailscaled.service
            Requires=tailscaled.service

            [Service]
            Type=oneshot
            ExecStart=/usr/local/bin/tailscale set --accept-dns=true
            RemainAfterExit=true

            [Install]
            WantedBy=multi-user.target
          EOT
        }
      ]
      extra_runcmd = [
        "systemctl daemon-reload",
        "systemctl enable --now tailscale-accept-dns.service",
      ]
    }
  ]

  # No worker nodes. Supported on v3.0.1 — v3.0.0 had a zero-agent plan bug
  # (kube-hetzner#2236 / #2238), so do not drop below 3.0.1 with this shape.
  agent_nodepools = []

  # REQUIRED for this shape. Despite kube.tf.example's comment claiming Klipper
  # turns this on automatically, locals.tf only forces it for a true single-node
  # cluster (total nodes == 1). Without this the control-plane NoSchedule taint
  # stays and nothing can schedule anywhere.
  allow_scheduling_on_control_plane = true

  # ---------------------------------------------------------------------------
  # Ingress: Klipper on node public IPs, Traefik owned by homelab-k8s
  # ---------------------------------------------------------------------------
  # No Hetzner managed load balancer, so no LB cost. Klipper binds :80/:443 on
  # each node's own public IP and forwards to the cluster's Traefik, which is
  # owned by homelab-k8s (`infra/traefik` wrapper chart) rather than this
  # module. `ingress_controller = "none"` is what keeps kube-hetzner from
  # installing its own Traefik via HelmChartConfig — the documented upstream
  # convention for "I run my own ingress." See homelab-k8s ADR-0004.
  #
  # Every node still has its own public IP, and replacing a node changes it —
  # Klipper listens on all local interfaces, so that's fine for direct access
  # to a specific node, but DNS needs one address that outlives any single
  # node. The control-plane floating IP above (nodes["0"].floating_ip) is that
  # address: it stays reachable across node replacement because Terraform
  # reassigns it to whatever server currently occupies that node slot. Point
  # real domains (via homelab-k8s's external-dns) at the floating IP, not a
  # node's own address.
  enable_klipper_metal_lb = true
  ingress_controller      = "none"

  # ---------------------------------------------------------------------------
  # Storage: none
  # ---------------------------------------------------------------------------
  # No PVCs in scope. Hetzner CSI defaults to true upstream, so it is explicitly
  # disabled. Either of these can be enabled later without rebuilding.
  enable_hetzner_csi = false
  enable_longhorn    = false

  # ---------------------------------------------------------------------------
  # Lifecycle: unattended patching
  # ---------------------------------------------------------------------------
  # Patch releases land without manual bumps. Leap Micro does transactional,
  # atomic OS upgrades and the module orchestrates the reboots via kured. Both
  # of these need the 3-node HA setup above to be safe.
  k3s_channel                      = "stable"
  automatically_upgrade_kubernetes = true
  automatically_upgrade_os         = true
}
