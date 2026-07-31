# Hetzner k3s Homelab — Design

**Status:** Approved (brainstorming)
**Date:** 2026-07-30
**Owner:** sirwayne
**Repo:** `opentofu-infra` (this repo)

## Goal

Minimal-cost, minimal-maintenance 3-node k3s cluster on Hetzner Cloud for personal
/homelab use. This spec covers the cluster bring-up only. Application deployment
(ArgoCD, Grafana, kube-prometheus, openclaw/hermes, dev experiments) is out of
scope and will be handled separately.

## Non-goals

- Production-grade HA across regions or zones
- Persistent stateful workloads (no databases, no file storage, no PVCs)
- Multi-tenant isolation
- Compliance / regulated workloads
- Public internet exposure of the kube API

## Constraints

- Personal/homelab use
- Minimal monthly cost
- Minimal maintenance overhead (set-and-forget, transactional OS updates, auto k3s patches)
- Operator is a single human with a static home IP
- Apply from home network only (no Tailscale, no Cloudflare Access)

## Decisions

### Topology

| Component       | Value                                                                     | Cost (monthly)   |
| --------------- | ------------------------------------------------------------------------- | ---------------- |
| Control plane   | 3 × `cx23` (2 vCPU, 4 GB RAM, 40 GB), `fsn1`, stacked etcd, HA            | 3 × €3.78 = €11.34 |
| Worker pools    | None — workloads schedule on control-plane nodes                          | —                |
| Ingress LB      | **Klipper LB** (`enable_klipper_metal_lb = true`) instead of Hetzner LB   | —                |
| Public IP       | 1 × Hetzner Floating IP, attached to one control-plane node               | €1.19            |
| Network         | One Hetzner private Network, `network_region = "eu-central"`              | free             |
| CNI             | Flannel (k3s default)                                                     | —                |
| Storage         | No Longhorn, no Hetzner CSI. PVCs not used in initial scope.              | —                |
| **Total infra** |                                                                           | **~€12.53**      |

Explicitly excluded: Tailscale, NAT router, cluster-autoscaler, multi-location
spread, Hetzner managed LB, IPv6 LB, second Hetzner network, Longhorn,
cert-manager, External Secrets, any application deployment.

**Klipper LB + Floating IP — failover note:** The Hetzner Floating IP lives on
one control-plane node. If that node dies, the public ingress is down until
the Floating IP is reassigned to another node. Hetzner supports moving a
Floating IP between servers via API; this is *not* automated by
`kube-hetzner` for klipper LB. For the 4-GB-RAM / single-LB homelab design,
this is an accepted tradeoff. If uptime becomes a real concern, either
re-evaluate (managed LB restores HA but costs €5.39/month more) or implement
a small Floating-IP-failover controller as a follow-up.

**Resource headroom note:** 4 GB RAM per node is tight for a busy cluster
running Prometheus, Grafana, and several apps. The design accepts this because
(a) the user's stated workload is light, (b) bumping to `cx33` is a
straightforward in-place resize on Hetzner if pressure shows up, and (c) most
light self-hosted apps are not memory-hungry. Memory usage should be watched
once monitoring is in place; if the cluster regularly sits above ~80% memory,
resize the control-plane nodepool to `cx33` rather than introducing workers.

### Distribution & lifecycle

- `kubernetes_distribution = "k3s"` (module default)
- `k3s_channel = "stable"` — auto-receives patch releases, no manual version
  bumps for routine CVEs. For a homelab, predictable-but-stale is not worth the
  maintenance tax.
- `automatically_upgrade_os = true` — Leap Micro does transactional, atomic OS
  upgrades and the module handles reboot orchestration. Disabling it just means
  we forget to update.
- Module version: pin to the current v3 stable tag at apply time and bump on
  release notes. (The repo's `kh-assistant` skill currently tracks v3.0.1 as the
  baseline; this spec is version-agnostic so the design survives minor bumps.)
- Packer image: existing `packer/hcloud-leapmicro-snapshots.pkr.hcl` (x86 only),
  snapshots live in `fsn1`. ARM `cax11` was considered and rejected — the
  packer snapshot could not be built for ARM at the time, so the cluster is
  x86-only. **Prereq:** the packer snapshot must exist in `fsn1` before the
  first `tofu apply` (build it with `packer build` from `terraform/k3s/packer/`
  when needed).

### Security

- `firewall_ssh_source = ["<home_ip>/32"]`
- `firewall_kube_api_source = ["<home_ip>/32"]`
- SSH: existing `id_ed25519` keypair, referenced from `terraform.tfvars`
- Hetzner API token: passed as `TF_VAR_hcloud_token` env var (never committed)
- No public managed Hetzner firewall for SSH or kube API from non-home IPs
- No Tailscale operator access (apply only from home)
- No OIDC for the kube API in v1 — single operator, static IP, client certs only
- No Cloudflare Access / Tunnel in v1 — Traefik is open to the public internet
  on :80/:443. Per-app rate-limiting / auth is a follow-up concern, applied at
  the application layer (out of scope for this design).

### GitOps layer

Out of scope for this design. Application deployment (including any GitOps
controller like ArgoCD or Flux) will be specified and implemented separately.

## Repo changes (this repo, `opentofu-infra`)

1. **Rewrite `terraform/k3s/kube.tf`** — gut the 1914-line template copy, keep
   only the actual config. Pin the module version.
2. **Add `terraform/k3s/terraform.tfvars.example`** — committed example
   showing the shape. `terraform.tfvars` is gitignored.
3. **Update `terraform/k3s/variable.tf`** — add `home_ip` variable (CIDR list
   string, with validation).
4. **Update `.gitignore`** — add `terraform.tfvars`, `*.tfstate*`, `.terraform/`,
   kubeconfig output files.
5. **Replace `README.md`** with a quickstart covering: prerequisites, Hetzner
   token export, `tofu init` / `tofu apply`, fetching the kubeconfig, and
   verifying cluster health. No app-layer instructions.
6. **No CI in v1.** GitHub Actions for `tofu fmt` / `tofu validate` / `tofu plan`
   can be added in a follow-up.

## Out of scope (deferred to follow-ups)

- Application deployment (ArgoCD, Flux, Helm releases, anything app-layer)
- `homelab-apps` repo and its layout
- External Secrets Operator + 1Password Connect
- cert-manager + ClusterIssuer + public-CA certificates
- Longhorn / replicated storage
- Cluster autoscaler
- Tailscale operator access
- GitHub Actions CI for Terraform
- Multi-location / multi-region spread
- Public IPv6 LB
- OIDC for the kube API
- Cloudflare Access in front of Traefik
- Backups / disaster recovery (volumes are ephemeral by design; cluster
  state worth backing up is the Terraform state file, not application data)

## Success criteria

- `tofu apply` from a freshly-cloned repo, with `TF_VAR_hcloud_token` set and a
  populated `terraform.tfvars`, provisions the 3-node k3s + LB in a single run.
- `kubectl get nodes` returns 3 `Ready` control-plane nodes after first apply.
- The kubeconfig output from Terraform authenticates against the cluster and
  can list namespaces.
- The public Traefik endpoint (via the Hetzner Floating IP and Klipper LB)
  responds with a Traefik default backend on :80.
- The cluster can be destroyed and recreated with no manual steps beyond
  `tofu destroy` followed by `tofu apply`.
- Monthly Hetzner cost stays at or under ~€20 (excluding traffic and snapshots).

## Open questions

None — all design questions resolved during brainstorming.

## References

- `kh-assistant` skill (live v3 baseline) — `/.agents/skills/kh-assistant/SKILL.md`
- `test-changes` skill (validate Terraform before commit) — `/.agents/skills/test-changes/SKILL.md`
- `running-stabilization-loop` skill (live matrix validation) — maintainer-only,
  not used in this design
