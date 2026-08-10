# Homelab ecosystem

This cluster does not exist in isolation. Three sibling repos cooperate to
run a home k8s homelab, each owning a different layer of the stack. This doc
maps the repos and the contracts that cross their boundaries. The `opentofu-infra`
README/AGENTS remain the source of truth for this repo's own invariants; this
doc is about the seams between the repos.

## Repos

| Repo | Layer | Role |
|---|---|---|
| `jrang188/opentofu-infra` (this repo) | Cluster provisioning | OpenTofu root module building the 3-node Hetzner k3s control-plane cluster (kube-hetzner v3.0.1, Tailscale transport, no agent nodepools, no storage). |
| `jrang188/homelab-nix` (private) | Home node OS | NixOS flake for `k3s-agent-hml`, a physical mini PC joined to the cluster as a k3s agent over Tailscale. sops-nix secrets, autoupgrade + drain hook replacing kured. |
| `jrang188/homelab-k8s` | Workloads / GitOps | ArgoCD-reconciled manifests: infra components (MetalLB, Traefik, sealed-secrets) and apps, via wrapper Helm charts and plain manifests. |

The cluster shape is: **3 Hetzner control planes** (this repo) +
**1 home agent node** (homelab-nix) = the schedulable pool. The control
planes hold etcd, are tainted `allow_scheduling_on_control_plane` so
workloads run on them, get unattended OS/k3s upgrades with kured-driven
reboots, and have **no** PVC storage class. The home node is `NoSchedule`-
tainted by default, has the only real local disk, and drains itself before
rebooting instead of relying on kured.

## Cross-repo contracts

### Tailscale tag convention

Shared naming for node identity in the Tailnet ACL, defined symmetrically in
`terraform/k3s/kube.tf` (control planes) and `homelab-nix`'s
`modules/tailscale.nix` (home agent):

- Control planes advertise `tag:k8s-control-plane`.
- The home agent advertises `tag:k8s-agent-home`.

Pattern is `tag:k8s-<role>` / `tag:k8s-<role>-<location>`. Both tags must be
owned in the Tailnet ACL's `tagOwners` before nodes authenticate cleanly.

### Tailscale private-route advertisement (homelab-nix ADR 0001)

The cluster's flannel runs on the Hetzner private network (`eth1`); the home
node has no presence there, only a Tailscale link. For the home node's own
pods to reach cluster services (ClusterIPs, DNS), each control plane must
advertise its own private IP as a Tailscale `/32` subnet route, and the home
agent must `--accept-routes`.

Implemented here in `terraform/k3s/kube.tf`:
`tailscale_node_transport.routing.advertise_node_private_routes = true`
(reboot-safe by construction — a `/32` drops with its node during rolling
upgrades). Requires one-time manual approval of the three routes in the
Tailscale admin console.

### The home node's k3s join

`homelab-nix`'s `modules/k3s-agent.nix` writes a k3s config with the agent's
runtime Tailscale IP as `node-ip` and `flannel-iface: tailscale0`, plus the
home labels/taints (`topology.kubernetes.io/zone=home`,
`node-role.kubernetes.io/home=true:NoSchedule`). It joins via the
`homelab.k3sAgent.serverAddr` (any reachable control plane's `*.ts.net:6443`);
k3s's client-side load balancer discovers the rest. Drain/uncordon around
reboots is a dedicated ServiceAccount created on the cluster, not in any repo.

### Secrets flow

Each repo has its own secrets mechanism; nothing is shared in plaintext:

- **opentofu-infra**: `TF_VAR_hcloud_token` / `TF_VAR_tailscale_auth_key`
  via 1Password (`op run`), local unencrypted state.
- **homelab-nix**: sops-nix, age key derived from the host's SSH key.
- **homelab-k8s**: sealed-secrets on the cluster.

## Status

- Control-plane private-route advertisement (`advertise_node_private_routes =
  true`): **landed and applied** in this repo.
- Home node `k3s-agent-hml`: **installed and live**; its first-install
  checklist (secrets, drain ServiceAccount, cluster-side setup) is complete.
- Planned, not yet built (tracked in `homelab-k8s`): Hermes Agent — an
  always-on LLM coding-agent daemon pinned to the home node, backed by
  home-node-scoped local-path storage, exposed via Tailscale rather than
  public ingress, and sandboxed with a gVisor RuntimeClass on the home node.
