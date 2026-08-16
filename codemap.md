# Repository Atlas: opentofu-infra

## Project Responsibility

Personal OpenTofu infra for a single Hetzner Cloud k3s cluster,
built on the `kube-hetzner` v3.0.1 community module. One live root
module (`terraform/k3s/`), 3-node control-plane shape, zero agent
nodes, Tailscale-only management, Klipper on node public IPs for
ingress, no storage. No CI; all validation runs locally through
pre-commit. One of three cooperating homelab repos (with `homelab-nix`
and `homelab-k8s`) — see `docs/homelab-ecosystem.md`.

## System Entry Points

- `terraform/k3s/kube.tf` — the only `module "kube-hetzner"` call in
  the repo.
- `terraform/k3s/onepassword.tf` — all secret sourcing (hcloud token,
  SSH keys, Tailscale auth key, ESO bootstrap token) via the
  `onepassword` provider; replaces `.env.tofu`/`TF_VAR_*` env vars.
- `terraform/k3s/secrets.tf` — the ESO bootstrap Secret
  (`external-secrets/onepassword-token`) delivered via write-only
  `data_wo`; a cross-repo contract with homelab-k8s.
- `terraform/k3s/terraform.tf` — version + provider pins
  (`~> 1.12` for OpenTofu; `hcloud ~> 1.62`, `kubernetes ~> 3.1`,
  `onepassword 3.3.1`).
- `terraform/k3s/packer/hcloud-leapmicro-snapshots.pkr.hcl` —
  prerequisite Hetzner snapshot.
- `pre-commit run --all-files` — the only validation surface
  (`fmt`, `validate`, `tflint`, `trivy`).
- `README.md` — setup, teardown, and operational notes.
- `docs/homelab-ecosystem.md` — the three-repo ecosystem and the
  contracts crossing repo boundaries (Tailscale tags, private-route
  advertisement).
- `docs/runbooks/` — operational recovery procedures.
- `docs/agents/` — conventions for agent sessions (issue tracker,
  triage labels, domain docs).
- `AGENTS.md` — hard rules and quirks for OpenCode sessions.
- `skills-lock.json` — content-addressed vendored skills
  (`.agents/skills/`, `.claude/skills/`), restorable via
  `npx skills add`.

## Directory Map

| Directory | Responsibility Summary | Detailed Map |
|---|---|---|
| `terraform/k3s/` | Live OpenTofu root module: single `kube-hetzner` v3.0.1 call, 3-node zero-agent cluster, Tailscale transport, 1Password-sourced secrets, ESO bootstrap Secret, Klipper ingress. | [View Map](terraform/k3s/codemap.md) |
| `terraform/k3s/packer/` | Builds the Leap Micro Hetzner snapshot the cluster module requires. Two templates live here; only the Leap Micro one is wired in. | [View Map](terraform/k3s/packer/codemap.md) |
| `terraform/` | Namespace container; one live root (`k3s/`). | [View Map](terraform/codemap.md) |
| `docs/` | Ecosystem doc (three-repo contracts), agent-session conventions, and operational runbooks. | [View Map](docs/codemap.md) |
| `docs/agents/` | Conventions for AI/agent sessions: domain docs, issue tracker, triage labels. | [View Map](docs/agents/codemap.md) |
| `docs/runbooks/` | Operational recovery procedures (CCM taint, join timeout, Tailscale routes). | [View Map](docs/runbooks/codemap.md) |

## Cross-Cutting Notes

- **Toolchain**: use `tofu`, not `terraform`. Pre-commit hooks are
  pinned via `--tf-path=tofu`. `tflint` and `trivy` are not installed
  by the toolchain; install them yourself.
- **Secrets**: sourced directly from 1Password via the `onepassword`
  provider, which authenticates through the local `op` CLI session —
  the machine running `tofu plan`/`apply` must have `op` installed
  and signed in (same category of requirement as the Tailscale login
  rule). No `TF_VAR_*` env vars and no `.env.tofu` file anymore.
- **State**: local and unencrypted; contains cluster-admin material.
  Enable `TF_ENCRYPTION` before the first apply on a new machine.
- **Hard rules** (full list in `AGENTS.md`): do not downgrade
  `kube-hetzner` below 3.0.1; do not remove
  `allow_scheduling_on_control_plane = true`; Tailscale auth key
  must be reusable and non-ephemeral; the operator host must be on
  the same Tailnet to apply, plan, SSH nodes, or run `kubectl`.
