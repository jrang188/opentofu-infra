# Directory Atlas: docs/

## Responsibility

The repo's cross-repo and operational documentation. This is the only
non-code, non-config documentation surface; the setup/teardown truth lives
in `README.md` and the agent hard rules in `AGENTS.md` — this folder holds
what neither covers: the three-repo ecosystem seams, agent-session
conventions, and recurring recovery procedures.

## Design

Three sub-areas, each a self-contained unit:

- `homelab-ecosystem.md` — the only top-level file. Maps the three
  cooperating repos (`opentofu-infra`, `homelab-nix`, `homelab-k8s`) and
  the contracts crossing their boundaries: the `tag:k8s-<role>` Tailscale
  tag convention, private-route advertisement (`10.255.0.0/16` /32 routes,
  `autoApprovers`), the home node's k3s join, and per-repo secrets flow.
  Cross-repo contracts, not repo-local invariants — `README.md`/`AGENTS.md`
  stay authoritative for those.
- `agents/` — conventions for AI/agent sessions: how to consume domain docs
  (`domain.md`), how to use the GitHub issue tracker (`issue-tracker.md`),
  and the triage label vocabulary (`triage-labels.md`).
- `runbooks/` — one file per recurring operational incident plus a
  `README.md` index. Symptom → root cause → fix structure; the goal is the
  second occurrence takes two minutes, not twenty.

## Flow

- `homelab-ecosystem.md` is read top-down: repos → cluster shape →
  cross-repo contracts (tags, routes, join, secrets) → status of each
  contract. It links out to `runbooks/tailscale-private-route-advertisement.md`
  for the incident write-up behind the routing contract.
- `agents/` docs are read by agent sessions before/during work:
  `domain.md` first (what to read before exploring), then the tracker and
  label docs when an issue needs creating, labelling, or resolving.
- `runbooks/README.md` is the entry index; each runbook is entered from a
  symptom (apply failure, stuck pods, unreachable home node) and walks to a
  verified fix. The join-timeout and CCM-taint runbooks cross-reference each
  other because the two failures co-occur.

## Integration

- Root `codemap.md` lists `docs/homelab-ecosystem.md` as a system entry
  point (sibling repos + cross-repo contracts).
- `README.md` links `docs/homelab-ecosystem.md` (top banner) and, from
  "Operational notes", `docs/runbooks/tailscale-ccm-uninitialized-taint.md`
  and `docs/runbooks/control-plane-join-timeout.md`.
- `AGENTS.md` (Agent skills section) points at `docs/agents/issue-tracker.md`,
  `docs/agents/triage-labels.md`, and `docs/agents/domain.md`.
- Runbook content reaches back into code: `terraform/k3s/kube.tf` and the
  vendored kube-hetzner module (`.terraform/modules/kube-hetzner/`) are the
  config surfaces the runbooks document and quote line numbers from.
