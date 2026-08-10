# Repository Atlas: opentofu-infra

## Project Responsibility

Personal OpenTofu infra for a single Hetzner Cloud k3s cluster,
built on the `kube-hetzner` v3.0.1 community module. One live root
module (`terraform/k3s/`), 3-node control-plane shape, zero agent
nodes, Tailscale-only management, Klipper on node public IPs for
ingress, no storage. No CI; all validation runs locally through
pre-commit.

## System Entry Points

- `terraform/k3s/kube.tf` — the only `module "kube-hetzner"` call in
  the repo.
- `terraform/k3s/terraform.tf` — version + provider pins
  (`~> 1.12` for OpenTofu, `~> 1.62` for `hcloud`).
- `terraform/k3s/packer/hcloud-leapmicro-snapshots.pkr.hcl` —
  prerequisite Hetzner snapshot.
- `pre-commit run --all-files` — the only validation surface
  (`fmt`, `validate`, `tflint`, `trivy`).
- `README.md` — setup, teardown, and operational notes.
- `docs/homelab-ecosystem.md` — the two sibling repos (`homelab-nix`,
  `homelab-k8s`) this cluster cooperates with and the contracts crossing
  repo boundaries (Tailscale tags, private-route advertisement).
- `AGENTS.md` — hard rules and quirks for OpenCode sessions.
- `skills-lock.json` — content-addressed vendored skills
  (`.agents/skills/`, `.claude/skills/`), restorable via
  `npx skills add`.

## Directory Map

| Directory | Responsibility Summary | Detailed Map |
|---|---|---|
| `terraform/k3s/` | Live OpenTofu root module: single `kube-hetzner` v3.0.1 call, 3-node zero-agent cluster with Tailscale transport and Klipper ingress. | [View Map](terraform/k3s/codemap.md) |
| `terraform/k3s/packer/` | Builds the Leap Micro Hetzner snapshot the cluster module requires. Two templates live here; only the Leap Micro one is wired in. | [View Map](terraform/k3s/packer/codemap.md) |
| `terraform/` | Namespace container; one live root (`k3s/`). | [View Map](terraform/codemap.md) |

## Cross-Cutting Notes

- **Toolchain**: use `tofu`, not `terraform`. Pre-commit hooks are
  pinned via `--tf-path=tofu`. `tflint` and `trivy` are not installed
  by the toolchain; install them yourself.
- **State**: local and unencrypted; contains cluster-admin material.
  Enable `TF_ENCRYPTION` before the first apply on a new machine.
- **Secrets**: pass via `TF_VAR_hcloud_token` and
  `TF_VAR_tailscale_auth_key` env vars. `terraform.tfvars` is
  gitignored but still on disk. `packer` reads `HCLOUD_TOKEN`, not
  `TF_VAR_hcloud_token`.
- **Hard rules** (full list in `AGENTS.md`): do not downgrade
  `kube-hetzner` below 3.0.1; do not remove
  `allow_scheduling_on_control_plane = true`; Tailscale auth key
  must be reusable and non-ephemeral; the operator host must be on
  the same Tailnet to apply, plan, SSH nodes, or run `kubectl`.
