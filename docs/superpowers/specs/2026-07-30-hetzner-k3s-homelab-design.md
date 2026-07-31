# Hetzner k3s Homelab — Design

**Status:** Approved (brainstorming)
**Date:** 2026-07-30
**Owner:** sirwayne
**Repo:** `opentofu-infra` (this repo)

## Goal

Minimal-cost, minimal-maintenance 3-node k3s cluster on Hetzner Cloud for personal
/homelab use. Workloads are mostly self-hosted apps (ArgoCD, Grafana, kube-prometheus,
openclaw/hermes) plus dev experimentation. No persistent data.

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
| Load balancer   | 1 × `lb11` in `fsn1`, public, fronts Traefik on :80 / :443                | €5.39            |
| Network         | One Hetzner private Network, `network_region = "eu-central"`              | free             |
| CNI             | Flannel (k3s default)                                                     | —                |
| Storage         | No Longhorn, no Hetzner CSI. PVCs not used in initial scope.              | —                |
| **Total infra** |                                                                           | **~€16.73**      |

Explicitly excluded: Tailscale, NAT router, cluster-autoscaler, multi-location
spread, IPv6 LB, second Hetzner network, Longhorn, cert-manager, External Secrets.

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
  x86-only.

### Security

- `firewall_ssh_source = ["<home_ip>/32"]`
- `firewall_kube_api_source = ["<home_ip>/32"]`
- SSH: existing `id_ed25519` keypair, referenced from `terraform.tfvars`
- Hetzner API token: passed as `TF_VAR_hcloud_token` env var (never committed)
- No public managed Hetzner firewall for SSH or kube API from non-home IPs
- No Tailscale operator access (apply only from home)
- No OIDC for the kube API in v1 — single operator, static IP, client certs only
- No Cloudflare Access / Tunnel in v1 — Traefik is open to the public internet
  on :80/:443, with rate-limiting / auth handled per-app when added via GitOps

### GitOps layer

The cluster is provisioned once via Terraform. Everything past bring-up is
GitOps.

**Terraform does:**

- Provision the cluster + LB
- One-time post-apply bootstrap (via `terraform_data` or `null_resource` +
  `local-exec`) that idempotently applies the `bootstrap/` directory:
  1. `argocd` namespace
  2. ArgoCD install (Helm release or raw manifests — pick whichever is smaller
     and more obvious)
  3. Root `Application` pointing at the `homelab-apps` Git repo

The bootstrap is idempotent: if the cluster is destroyed and recreated, a
re-apply of Terraform re-runs the bootstrap and ArgoCD syncs the rest of the
stack from Git.

**ArgoCD owns (in a separate `homelab-apps` repo, not this one):**

- ArgoCD self-config
- IngressRoutes, cert-manager ClusterIssuer (added when the first real app
  needs HTTPS)
- kube-prometheus-stack, Grafana dashboards
- openclaw / hermes
- Dev / experimentation apps

**Day-to-day flow:**

- Add an app → write manifests (or Helm values) under
  `homelab-apps/apps/<name>/`, push. ArgoCD picks it up.
- Upgrade an app → bump version in values, push.
- Cluster dies → `tofu apply` from home; bootstrap reapplies; apps self-sync.

### Secrets

None in v1. The current planned workload mix (argocd, kube-prometheus, grafana,
openclaw) does not need external secrets.

When a real need shows up, add **External Secrets Operator + 1Password Connect**
in a follow-up. That follow-up will:

- Run 1Password Connect as a Deployment in the cluster
- Bootstrap the Connect token manually with `kubectl create secret` once after
  cluster bring-up (chicken-and-egg)
- Use `ClusterSecretStore` + `ExternalSecret` for everything else

## Repo changes (this repo, `opentofu-infra`)

1. **Rewrite `terraform/k3s/kube.tf`** — gut the 1914-line template copy, keep
   only the actual config. Pin the module version.
2. **Add `terraform/k3s/terraform.tfvars.example`** — committed example
   showing the shape. `terraform.tfvars` is gitignored.
3. **Add `terraform/k3s/bootstrap/`** — ArgoCD bootstrap manifests
   (`00-namespace.yaml`, `argocd-install.yaml`, `root-app.yaml`).
4. **Update `terraform/k3s/variable.tf`** — add `home_ip` variable (CIDR list
   string, with validation).
5. **Update `.gitignore`** — add `terraform.tfvars`, `*.tfstate*`, `.terraform/`,
   kubeconfig output files.
6. **Replace `README.md`** with a quickstart covering: prerequisites, Hetzner
   token export, `tofu init` / `tofu apply`, fetching the kubeconfig, reaching
   the ArgoCD UI, and the link to the `homelab-apps` repo.
7. **No CI in v1.** GitHub Actions for `tofu fmt` / `tofu validate` / `tofu plan`
   can be added in a follow-up.

## Out of scope (deferred to follow-ups)

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
- Backups / disaster recovery (volumes are ephemeral by design; the only state
  worth backing up is the `homelab-apps` Git repo, which is already in Git)

## Success criteria

- `tofu apply` from a freshly-cloned repo, with `TF_VAR_hcloud_token` set and a
  populated `terraform.tfvars`, provisions the 3-node k3s + LB in a single run.
- ArgoCD is reachable, synced, and watching the `homelab-apps` repo at the end
  of the first apply.
- All planned apps (kube-prometheus, grafana, argocd, openclaw) are installable
  by pushing manifests to `homelab-apps` — no further `tofu apply` required.
- The cluster can be destroyed and recreated with no manual steps beyond
  `tofu destroy` followed by `tofu apply`.
- No `tofu apply` is required to add, change, or remove an app.
- Monthly Hetzner cost stays at or under ~€20 (excluding traffic and snapshots).

## Open questions

None — all design questions resolved during brainstorming.

## References

- `kh-assistant` skill (live v3 baseline) — `/.agents/skills/kh-assistant/SKILL.md`
- `test-changes` skill (validate Terraform before commit) — `/.agents/skills/test-changes/SKILL.md`
- `running-stabilization-loop` skill (live matrix validation) — maintainer-only,
  not used in this design
