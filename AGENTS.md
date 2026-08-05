# AGENTS.md

Repo: personal OpenTofu infra for a single Hetzner k3s cluster via the
`kube-hetzner` v3.0.1 module. One live root module: `terraform/k3s/`.
The README is the source of truth for setup, teardown, and operational
caveats — do not duplicate it here.

## Tooling

- Use `tofu`, not `terraform`. pre-commit hooks are pinned to `tofu`
  via `--tf-path=tofu`; the toolchain installs neither `tflint` nor
  `trivy` (see README "Development").
- OpenTofu `~> 1.12` (floor 1.10.1 from the module). Provider `hcloud`
  is major-pinned `~> 1.62` to block a silent 2.x bump — keep the pin,
  commit `.terraform.lock.hcl`.
- No test framework, no language runtime — all verification is via
  `pre-commit run --all-files` and the `tofu plan/apply` flow described
  in the README.

## Hard rules (read these before touching `terraform/k3s/kube.tf`)

- **Do not downgrade `kube-hetzner` below 3.0.1.** v3.0.0 has a
  zero-agent plan bug (kube-hetzner#2236 / #2238). This config runs
  zero agent nodepools, so it is on the buggy path.
- **`allow_scheduling_on_control_plane = true` is mandatory.** It is
  not auto-derived from "no agents"; without it the NoSchedule taint
  stays and nothing schedules. Don't "clean it up".
- **Tailscale is the only node transport.** Public SSH and the public
  kube API are closed. Any agent that wants to SSH a node or run
  `kubectl` from this machine must do it over the Tailnet, so the
  machine running `tofu apply` (or `tofu plan`) must be logged in.
- **Tailscale auth key must be reusable and non-ephemeral.** Ephemeral
  keys reap nodes on offline, which is correct for autoscalers and
  wrong for these static control planes.
- **Packer is a real prerequisite.** The cluster module looks up the
  Leap Micro snapshot by label
  `leapmicro-snapshot=yes,kube-hetzner/k8s-distro=k3s` and fails if it
  is missing. `terraform/k3s/packer/hcloud-leapmicro-snapshots.pkr.hcl`
  builds it; the sibling `hcloud-microos-snapshots.pkr.hcl` is
  reference-only and is not used by this cluster — leave it alone.

## Secrets and state

- State is **local and unencrypted** in this repo and contains the
  Tailscale auth key, the k3s cluster token, and the kubeconfig. Pass
  secrets via `TF_VAR_hcloud_token` / `TF_VAR_tailscale_auth_key`
  env vars, never in `terraform.tfvars` (which is gitignored but still
  on disk). The README's "Operational notes" flag enabling
  `TF_ENCRYPTION` as a follow-up — do that before the first apply if
  you are setting up a new machine.
- `packer` reads `HCLOUD_TOKEN` from the env, not `TF_VAR_hcloud_token`.

## Vendored skills (`.agents/skills/`, `.claude/skills/`)

These directories are gitignored and restored from `skills-lock.json`
(`npx skills add ...`). They are not project code. For any Terraform /
OpenTofu work in this repo, load the matching skill first:

- `terraform-skill` — diagnose-first guidance for any TF/OpenTofu
  change, with risk-category routing and a response contract.
- `test-changes` — the repo's validation flow (fmt, validate, plan
  against a real test cluster).
- `sync-docs`, `upgrade-cluster`, `debug-node`,
  `running-stabilization-loop` — cluster lifecycle and recovery.
- `kh-assistant` — entry point for "how do I do X in kube-hetzner".

Don't edit files under `.agents/skills/` or `.claude/skills/`
directly — they are content-addressed by the lockfile.

## Pre-commit quirks

- First-run `terraform_validate` does a real `tofu init` against the
  network; it is the slowest hook and the only one that needs
  connectivity. Later runs reuse the cached `.terraform/`.
- `terraform_tflint` uses `.tflint.hcl`, which sets
  `call_module_type = "local"` — tflint will not descend into the
  vendored kube-hetzner module under `.terraform/`. Treat
  `terraform_tflint` failures on paths under `.terraform/` as
  misconfig, not as findings.
- `terraform_trivy` is invoked with `--skip-dirs=**/.terraform` for
  the same reason. Do not drop that flag.
- `terraform_fmt` runs from the repo root and is recursive — it
  formats every `.tf` file under `terraform/`, including the
  untouched microos packer template.

## Repository Map

A full codemap is available at `codemap.md` in the project root.

Before working on any task, read `codemap.md` to understand:
- Project architecture and entry points
- Directory responsibilities and design patterns
- Data flow and integration points between modules

For deep work on a specific folder, also read that folder's
`codemap.md`.

## When a task is unclear

If a request would change cluster topology (nodepool shape, ingress
mode, transport, storage) or cross the kube-hetzner module version
floor, stop and read the relevant section of `README.md` before
proposing a diff. The README's "Operational notes" lists the
explicit invariants this cluster depends on.
