# terraform/k3s/

## Responsibility

The only live OpenTofu root module in the repo. Provisions a 3-node
k3s control-plane cluster on Hetzner Cloud by wrapping the
`kube-hetzner` v3.0.1 community module. No agent nodes, no managed
load balancer, no storage — workloads schedule on the control planes
via Tailscale-only management and Klipper on the node public IPs.

## Design

Single `module "kube-hetzner"` call in `kube.tf`, split across small
files by concern:

- `kube.tf` — the module block. Hard rules here: do not downgrade
  below 3.0.1 (zero-agent plan bug, kube-hetzner#2236/#2238); keep
  `allow_scheduling_on_control_plane = true` (locals only force it
  for single-node clusters, this is a 3-node zero-agent shape);
  `node_transport_mode = "tailscale"` with `bootstrap_mode =
  "cloud_init"` (the default `remote_exec` bootstrap has no public
  SSH to use, so Tailscale must come up from cloud-init before
  Terraform ever connects).
- `terraform.tf` — pins `required_version = "~> 1.12"` (module floor
  is 1.10.1) and `hcloud ~> 1.62` (major pin to block a silent 2.x
  bump). `.terraform.lock.hcl` is committed.
- `providers.tf` — wires `provider "hcloud"` with `var.hcloud_token`.
- `variables.tf` — seven variables: `cluster_name` (regex-validated
  lowercase/digits/dashes), `hcloud_token` (sensitive),
  `ssh_public_key_path` + `ssh_private_key_path` (default
  `~/.ssh/id_ed25519[.pub]`, must be a matching pair) with `ssh_public_key` +
  `ssh_private_key` as content overrides (sensitive, injected via 1Password
  env vars, win over the paths), `tailscale_auth_key` (sensitive, must be
  reusable and non-ephemeral), `tailscale_magicdns_domain` (regex-validated
  `*.ts.net`).
- `terraform.tfvars.example` — copy to `terraform.tfvars`
  (gitignored). Secrets via `TF_VAR_*` env vars, not in this file.
- `outputs.tf` — `control_planes_public_ipv4` (the IPs Klipper serves
  `:80`/`:443` on) and `kubeconfig` (sensitive; extract with
  `tofu output -raw kubeconfig`).
- `packer/` — subdir, see its own map.

Cluster shape: 3 × `cx23` in `fsn1`, `k3s stable` channel,
`automatically_upgrade_kubernetes = true`,
`automatically_upgrade_os = true`, `enable_klipper_metal_lb = true`,
`ingress_controller = "traefik"`, `ingress_replica_count = 3`
(autodetect resolves to 1 with zero agents), `enable_hetzner_csi =
false`, `enable_longhorn = false`, `firewall_kube_api_source = null`,
`firewall_ssh_source = null` (the module rejects world-open values
in Tailscale mode).

## Flow

Apply (per the README, repeated here because the order is the point):

1. `tofu init` — downloads the module, populates `.terraform/`.
2. `tofu plan -out=k3s.tfplan` — must be reviewed before apply;
   kube-hetzner surfaces drift in plan.
3. `tofu apply k3s.tfplan` — must run on a host logged in to the
   same Tailscale Tailnet as the auth key. There is no public SSH
   fallback.
4. `tofu output -raw kubeconfig > k3s_kubeconfig.yaml` (file is
   gitignored).
5. `KUBECONFIG=terraform/k3s/k3s_kubeconfig.yaml kubectl get nodes`
   — expect three `Ready` control-plane nodes.

Teardown is the same shape with `-destroy`. If the Hetzner CCM races
the LB detach on the way out, the upstream `scripts/destroy.sh` in
the kube-hetzner repo handles the retry and prints an orphan report.

## Integration

- Consumes: the snapshot built by `terraform/k3s/packer/`, the
  Hetzner Cloud API (`TF_VAR_hcloud_token`), the Tailscale Tailnet
  (auth key + machine membership for the operator), a local SSH
  keypair.
- Consumed by: the operator running `tofu apply` from a
  Tailnet-joined host; cluster workloads via Klipper on each node's
  public IP. State is local and unencrypted, so any host running
  apply becomes cluster-admin — enable `TF_ENCRYPTION` before the
  first apply on a new machine.
