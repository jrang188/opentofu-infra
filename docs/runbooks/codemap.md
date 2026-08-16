# Directory Atlas: docs/runbooks/

## Responsibility

Recurring operational recovery procedures for this cluster: how to
recognize each problem, why it happens, and the exact fix. One file per
incident; add a new one any time a diagnosis takes more than a few minutes.
These are the expanded step-by-step version of the short invariants/gaps
listed in `README.md`'s "Operational notes".

## Design

- `README.md` — the index: one-line symptom triggers linking each runbook,
  plus a note on when to add a new file.
- One file per recurring incident, each following a symptom → root cause →
  fix structure, with "when this recurs" and "longer-term fix" sections
  where relevant:
  - `control-plane-join-timeout.md` — `tofu apply` exit 124 on
    `terraform_data.control_planes` during simultaneous multi-control-plane
    bootstrap. A fixed-timeout (360s) race in the module's post-install
    poll, not a real failure; verify k3s health over Tailscale, then
    re-run `make plan && make apply`.
  - `tailscale-ccm-uninitialized-taint.md` — pods stuck `Pending` and the
    `node.cloudprovider.kubernetes.io/uninitialized` taint never cleared.
    Hetzner CCM can't match nodes registered with Tailscale IPs; fix is
    `k3s kubectl taint nodes --all ...uninitialized-`. No persistent fix;
    recurs after every reboot/node recreate.
  - `tailscale-private-route-advertisement.md` — home node has no route to
    the Hetzner private subnet (`10.255.0.0/16`), breaking remotedialer and
    pod API access. Root cause: kube-hetzner `ignore_changes` on
    `user_data`. Documents the manual re-advertise, ACL `autoApprovers`,
    and the `tailscale-accept-dns.service` workaround for the module's
    hardcoded `--accept-dns=false`.
- Runbooks cross-reference each other where failures co-occur (join-timeout
  is usually accompanied by the CCM taint).

## Flow

- Enter via `README.md` from a symptom, or directly from `README.md`'s
  "Operational notes" (top-level `README.md`, not this folder's).
- Each runbook is a linear path: confirm the symptom → confirm the root
  cause (often via SSH/journalctl over the Tailnet) → apply the exact
  fix → verify. The private-route runbook additionally records what was
  done, verification commands, a deferred rolling-recreate, and lessons
  learned (2026-08-16, opentofu-infra#3).

## Integration

- Top-level `README.md` links `tailscale-ccm-uninitialized-taint.md` and
  `control-plane-join-timeout.md` from "Operational notes".
- `docs/homelab-ecosystem.md` links `tailscale-private-route-advertisement.md`
  as the write-up behind the `advertise_node_private_routes = true` contract.
- The runbooks quote the config surfaces they document:
  `terraform/k3s/kube.tf` (Tailscale transport settings, `extra_runcmd` /
  `extra_write_files`) and the vendored kube-hetzner module
  (`.terraform/modules/kube-hetzner/control_planes.tf:783`, `locals.tf:423`,
  `modules/host/main.tf:62-69`).
