# Tailscale CCM leaves nodes tainted `uninitialized`

## Symptom

One or more of:

- `tofu apply` hangs or fails during the kustomization step, e.g.:
  ```
  kubectl -n system-upgrade wait --for=condition=available --timeout=900s deployment/system-upgrade-controller
  ```
  never returns / times out.
- Workload pods (any of them, not just `system-upgrade-controller`) stuck `Pending`.
- `journalctl -u k3s` on a control plane repeats, forever:
  ```
  level=info msg="Network policy controller waiting for removal of node.cloudprovider.kubernetes.io/uninitialized taint"
  ```
- `kubectl describe node <node>` shows taint `node.cloudprovider.kubernetes.io/uninitialized:NoSchedule`.

## Root cause

kube-hetzner's `node_transport_mode = "tailscale"` registers nodes with
private Tailscale IPs and no `node-external-ip`. The Hetzner Cloud Controller
Manager can't match the node against the Hetzner API by that IP, so it never
clears the taint it sets at node registration. This is a module gap,
confirmed unfixed through kube-hetzner v3.1.0 — see `README.md`'s
"Operational notes" for the tracking context.

It is **not** something that resolves on its own, and it is **not** specific
to a fresh apply — it recurs any time a node's kubelet restarts.

## Fix

SSH to any one control plane over Tailscale (it has full API access to taint
every node) and run, as root:

```bash
k3s kubectl taint nodes --all node.cloudprovider.kubernetes.io/uninitialized-
```

No kubeconfig extraction needed — `k3s kubectl` talks to the local API
server directly, using k3s's own admin credentials on disk.

Confirm it worked:

```bash
k3s kubectl get pods -n system-upgrade -o wide
k3s kubectl get nodes -o wide
```

If a `tofu apply` is mid-flight and stuck on the `system-upgrade-controller`
wait, clearing the taint lets `system-upgrade-controller`'s pod schedule and
go Ready within seconds — the apply should pick this up and proceed on its
own within its existing timeout window. If the apply already errored out,
clear the taint first, then retry `make plan && make apply`.

## When this recurs

- After every node reboot / kubelet restart, including kured-driven Leap
  Micro transactional-update reboots.
- After every node replacement or full cluster destroy/recreate.

There is no persistent fix available today. The closest attempted
workaround — a `node-untainter` DaemonSet that re-applied the taint removal
on a loop — was tried and removed; see `README.md`.

## Longer-term fix (not yet available)

Set `node-external-ip` on each control plane so the CCM can match nodes by
their public IP instead. `control_planes_custom_config` cannot currently
express per-node values for this, so it's blocked on either an upstream
kube-hetzner fix or a different mechanism for setting it per node.
