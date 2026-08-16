# terraform/k3s/

## Responsibility

The only live OpenTofu root module in the repo. Provisions a 3-node
k3s control-plane cluster on Hetzner Cloud by wrapping the
`kube-hetzner` v3.0.1 community module. No agent nodes, no managed
load balancer, no storage — workloads schedule on the control planes
via Tailscale-only management and Klipper on the node public IPs.
All secrets are sourced from 1Password via the `onepassword`
provider, which authenticates through the local `op` CLI session
(desktop app, not a service account).

## Design

Single `module "kube-hetzner"` call in `kube.tf`, split across small
files by concern:

- `kube.tf` — the module block. Hard rules here: do not downgrade
  below 3.0.1 (zero-agent plan bug, kube-hetzner#2236/#2238); keep
  `allow_scheduling_on_control_plane = true` (locals only force it
  for single-node clusters, this is a 3-node zero-agent shape);
  `node_transport_mode = "tailscale"` with `bootstrap_mode =
  "cloud_init"` (with `firewall_ssh_source = null` there is no public
  SSH for the default `remote_exec` bootstrap, so Tailscale must come
  up from cloud-init before Terraform ever connects). The
  `tailscale_node_transport` block sets `magicdns_domain`, an
  `auth_key` auth mode advertising `tag:k8s-control-plane` (shared
  tag convention with homelab-nix), and `advertise_node_private_routes
  = true` so Tailscale-only agents get a route back to flannel's
  node-ips (one-time manual route approval in the Tailscale admin
  console; see `../../../homelab-nix/docs/adr/0001-...`). A systemd
  unit via `extra_write_files`/`extra_runcmd` re-enables
  `--accept-dns=true` on every boot — kube-hetzner hardcodes
  `--accept-dns=false` in its bootstrap script, but k3s etcd peer TLS
  requires MagicDNS — see
  `docs/runbooks/tailscale-private-route-advertisement.md`.
  `firewall_kube_api_source = null` and `firewall_ssh_source = null`
  close public access entirely; access comes from the Tailnet.
- `onepassword.tf` — secret sourcing, replacing `.env.tofu` /
  `op run --env-file=.env.tofu` / `TF_VAR_*` injection.
  `provider "onepassword" {}` is intentionally empty and
  authenticates via the local `op` CLI session, so the machine
  running `tofu plan`/`tofu apply` must have `op` installed and
  signed in. Ephemeral `onepassword_item` resources are used only
  where the consuming argument accepts ephemeral values: provider
  `hcloud` auth (`providers.tf`) and the write-only `data_wo` payload
  (`secrets.tf`). The module's own inputs (`hcloud_token`,
  `ssh_public_key`, `ssh_private_key`, `tailscale_auth_key`) are not
  declared `ephemeral = true` upstream and the module re-stores
  `hcloud_token` into its own k8s Secret, so ephemeral values are
  rejected there — plain `onepassword_item` data sources are used
  instead: no env-var file, but the value is unavoidably readable in
  state.
- `secrets.tf` — bootstrap Secret for the External Secrets
  Operator's ClusterSecretStore. Per ADR-0006, the 1Password
  service-account token ESO needs cannot come from ESO (circular);
  Terraform delivers it outside ArgoCD's reconciliation loop. Cross-
  repo contract: homelab-k8s `infra/eso` references this Secret by
  exact name/namespace/key (`external-secrets` / `onepassword-token`
  / `token`) — changing any of those breaks the contract. The token
  is written via the provider's write-only `data_wo` attribute, so it
  never lands in state or plan output. Rotation = bump the token in
  1Password, bump `var.onepassword_service_account_token_revision`
  by 1, re-apply — `data_wo` is only written when `data_wo_revision
  >= 1` and only re-pushed when it changes. The revision used to be
  auto-derived from a SHA-256 hash of the token, but an ephemeral
  value stays ephemeral through function calls, so it cannot feed
  this plain argument: auto-detection was traded for never letting
  the token touch state. The namespace resource has
  `lifecycle { ignore_changes = all }` because homelab-k8s's ESO
  Helm chart also targets it (`CreateNamespace=true`) and takes over
  ownership after creation.
- `terraform.tf` — pins `required_version = "~> 1.12"` (module floor
  is 1.10.1) and three providers: `hcloud ~> 1.62` (major pin to
  block a silent 2.x bump), `kubernetes ~> 3.1` (matches the module's
  floor, blocks a future 4.x), `onepassword 3.3.1` (pinned exactly).
  `.terraform.lock.hcl` is committed (currently hcloud 1.68.0,
  kubernetes 3.2.1).
- `providers.tf` — wires three providers: `hcloud` (token from
  `ephemeral.onepassword_item.hcloud_token.credential`, fetched fresh
  each phase, never in state), `kubernetes` (host + base64-decoded
  certs from `module.kube-hetzner.kubeconfig_data` — the same
  reference the module's own providers-k8s.tf uses; the host is a
  private Tailscale IP and the provider fields are not marked
  sensitive, so they show in plan output, acceptable given local
  state), and `onepassword` (fixed account UUID; the empty block
  authenticates via the `op` CLI session).
- `variables.tf` — three variables only: `cluster_name`
  (regex-validated lowercase/digits/dashes, default `"k3s"`),
  `onepassword_service_account_token_revision` (manually-bumped
  counter that gates/re-pushes the write-only `data_wo`), and
  `tailscale_magicdns_domain` (regex-validated `*.ts.net`). The old
  token/key/SSH variables are gone — those values are sourced from
  1Password via `onepassword.tf`.
- `outputs.tf` — `control_planes_public_ipv4` (the IPs Klipper serves
  `:80`/`:443` on) and `kubeconfig` (sensitive; extract with
  `tofu output -raw kubeconfig`).
- `terraform.tfvars.example` — copy to `terraform.tfvars`
  (gitignored). Holds only `cluster_name` and
  `tailscale_magicdns_domain`; no secrets, none injected by env.
- `packer/` — subdir, see its own map.

Cluster shape: 3 × `cx23` in `fsn1`, `k3s stable` channel,
`automatically_upgrade_kubernetes = true`,
`automatically_upgrade_os = true`, `enable_klipper_metal_lb = true`,
`ingress_controller = "none"` (Traefik owned by homelab-k8s;
kube-hetzner's built-in Traefik disabled per ADR-0004),
`enable_hetzner_csi = false`, `enable_longhorn = false`,
`firewall_kube_api_source = null`, `firewall_ssh_source = null` (the
module rejects world-open values in Tailscale mode).

## Flow

Apply (per the README, repeated here because the order is the point).
No Makefile and no `op run` wrapping — secrets come from 1Password
at each phase via the provider:

1. `tofu init` — downloads the module, populates `.terraform/`.
2. `tofu plan -out=k3s.tfplan` — must be reviewed before apply;
   kube-hetzner surfaces drift in plan.
3. `tofu apply k3s.tfplan` — must run on a host logged in to the
   same Tailscale Tailnet as the auth key AND with `op` installed and
   signed in (1Password desktop app session). There is no public SSH
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
  Hetzner Cloud API (`hcloud_token` from 1Password), the Tailscale
  Tailnet (auth key + machine membership for the operator), and SSH
  keys + the ESO service-account token from 1Password
  (`onepassword.tf`).
- Consumed by: the operator running `tofu apply` from a
  Tailnet-joined host with an `op` session; cluster workloads via
  Klipper on each node's public IP; homelab-k8s's `infra/eso`
  ClusterSecretStore reading the `onepassword-token` Secret written
  by `secrets.tf` (exact name/namespace/key contract).
- Sibling repos: homelab-k8s owns cluster ingress (Traefik wrapper
  chart, ADR-0004) and the ESO ClusterSecretStore that consumes the
  bootstrap Secret; homelab-nix shares the `tag:k8s-*` Tailscale tag
  convention and documents the private-route advertisement for its
  home agent (ADR-0001).
- Runbooks: `docs/runbooks/tailscale-private-route-advertisement.md`
  (accept-dns unit + /32 route advertisement),
  `docs/runbooks/tailscale-ccm-uninitialized-taint.md`,
  `docs/runbooks/control-plane-join-timeout.md`, plus
  `docs/homelab-ecosystem.md` for the surrounding ecosystem.
- State is local and unencrypted, so any host running apply becomes
  cluster-admin — enable `TF_ENCRYPTION` before the first apply on a
  new machine.
