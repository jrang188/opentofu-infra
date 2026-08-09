module "kube-hetzner" {
  source  = "kube-hetzner/kube-hetzner/hcloud"
  version = ">= 3.0.1, < 4.0.0"

  providers = {
    hcloud = hcloud
  }

  hcloud_token   = var.hcloud_token
  cluster_name   = var.cluster_name
  network_region = "eu-central"

  # SSH keys: content wins when provided (1Password via TF_VAR_ssh_*), otherwise
  # fall back to the *_path variables. The conditional is lazy, so file() only
  # runs on the path branch and never on a null default.
  ssh_public_key  = var.ssh_public_key != null ? var.ssh_public_key : file(var.ssh_public_key_path)
  ssh_private_key = var.ssh_private_key != null ? var.ssh_private_key : file(var.ssh_private_key_path)

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
  tailscale_auth_key  = var.tailscale_auth_key

  tailscale_node_transport = {
    bootstrap_mode  = "cloud_init"
    magicdns_domain = var.tailscale_magicdns_domain

    auth = {
      mode = "auth_key"
    }

    routing = {
      # Single Hetzner Network and no external-network nodepools, so no
      # node-private /32 routes need advertising and no Tailnet route approvals
      # are required. Must become true if external-network nodepools are added.
      advertise_node_private_routes = false
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
      count       = 3
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
  # Ingress: Klipper on node public IPs
  # ---------------------------------------------------------------------------
  # No Hetzner managed load balancer, so no LB cost. Klipper binds :80/:443 on
  # each node's own public IP and forwards to Traefik.
  #
  # Tradeoff: there is no stable public address. Every node has its own IP and
  # replacing a node changes it, so DNS pointed at a node IP breaks on node
  # replacement. Fine while nothing public depends on it — revisit before
  # pointing a real domain here (a Floating IP or managed LB solves this).
  enable_klipper_metal_lb = true
  ingress_controller      = "traefik"

  # One Traefik pod per node. The autodetect default (0) resolves to 1 replica
  # when there are zero agent nodes, which would serve all ingress from a single
  # pod on a single node.
  ingress_replica_count = 3

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
