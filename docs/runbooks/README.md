# Runbooks

Recurring operational issues for this cluster: how to recognize them, why
they happen, and the exact fix. Add a new file here the next time you spend
more than a few minutes diagnosing something — the goal is that the second
occurrence takes two minutes, not twenty.

- [Tailscale CCM leaves nodes tainted `uninitialized`](tailscale-ccm-uninitialized-taint.md) — pods stuck `Pending`, `system-upgrade-controller` never comes up. Happens after every reboot and every node recreate.
- [Control plane join times out during simultaneous bootstrap](control-plane-join-timeout.md) — `tofu apply` fails with exit 124 on `terraform_data.control_planes` right after a multi-control-plane destroy/recreate.
- [Tailscale private-route advertisement fix](tailscale-private-route-advertisement.md) — home node has no route to Hetzner private subnet, breaking remotedialer and pod API access. Root cause: kube-hetzner ignores `user_data` changes on existing servers.

See `README.md`'s "Operational notes" for the short version of known
invariants and gaps; these runbooks are the expanded step-by-step version for
the ones that recur.
