# Tailscale private-route advertisement fix

Date: 2026-08-16
Issue: opentofu-infra#3
Scope: `terraform/k3s/` — kube-hetzner v3.1.0, Tailscale transport

## Problem

The home node (`k3s-agent-hml`) had no route to the Hetzner private subnet
(`10.255.0.0/16`), breaking:

1. **k3s remotedialer** — `kubectl logs`/`exec`/`port-forward` for home-node
   pods 502'd unconditionally.
2. **Pod API access** — any pod on the home node calling
   `kubernetes.default.svc` (`10.43.0.1:443`) timed out, causing
   `local-path-provisioner` to crash-loop.

## Root cause

`advertise_node_private_routes = true` was set in `kube.tf` (commit
`36de473`, 2026-08-09), and the rendered `cloudinit_config` in state had the
correct `tailscale up --advertise-routes=…` script. But kube-hetzner's
`hcloud_server` resource has `user_data` in `lifecycle.ignore_changes`
(`modules/host/main.tf:62-69`), so the existing control planes were never
recreated. They booted with the pre-change cloud-init (advertise=false) and
never advertised routes.

The same mechanism means ANY cloud-init-affecting change (routes, tags, DNS
settings) requires manual server recreation — `tofu apply` alone is a no-op
for the running servers.

## What was done

### 1. Manual route advertisement

SSH'd over the Tailnet to each control plane and ran:

```
tailsup --accept-dns=false --accept-routes \
  --advertise-routes=<node-private-ip>/32 \
  --advertise-tags=tag:k8s-control-plane \
  --snat-subnet-routes=false \
  --hostname=<node-name>
```

Private IPs: `10.255.0.1` (iws), `10.255.0.2` (ugu), `10.255.0.3` (nbg).

Verified via `tailscale debug netmap` that `SelfNode.Hostinfo.RoutableIPs`
showed the `/32` route for each node.

### 2. Tailnet ACL — autoApprovers

Added to the Tailnet ACL policy (manual admin-console action):

```json
"autoApprovers": {
  "routes": {
    "10.255.0.0/16": ["tag:k8s-control-plane"]
  }
}
```

`10.255.0.0/16` (the actual subnet, not `/24`) covers all three `/32`s. Per
Tailscale docs, a broader prefix auto-approves more-specific advertised
routes.

### 3. Re-triggered advertisement

Auto-approvers only apply when a route is *first* advertised (per Tailscale
docs). Ran a clear + re-advertise cycle on each node to trigger approval:

```
tailscale up --reset --accept-dns=false --accept-routes \
  --advertise-tags=tag:k8s-control-plane --hostname=<name>
# then:
tailscale up --accept-dns=false --accept-routes \
  --advertise-routes=<ip>/32 --advertise-tags=tag:k8s-control-plane \
  --snat-subnet-routes=false --hostname=<name>
```

Verified `PrimaryRoutes` now shows the `/32` on all 3 nodes (from both the
node's own `tailscale status --json` and the peer view on sterling-mbp).

### 4. Secondary fix — `--accept-dns=false` breaks etcd peer TLS

During the clear+re-advertise cycle, `tailscale up --reset` with
`--accept-dns=false` broke Tailscale MagicDNS on the control planes. k3s
etcd peer TLS verification requires DNS resolution of Tailscale hostnames
(e.g. `k3s-control-plane-iws.tail8255cc.ts.net`), which only works via
MagicDNS (`100.100.100.100`). Without it, etcd peers rejected each other's
TLS connections and nodes went `NotReady`.

**Fix:** Re-enabled `--accept-dns` on all 3 nodes, then deployed a systemd
service to persist across reboots:

```ini
# /etc/systemd/system/tailscale-accept-dns.service
[Unit]
Description=Re-enable Tailscale MagicDNS for k3s etcd peer TLS
After=tailscaled.service
Requires=tailscaled.service

[Service]
Type=oneshot
ExecStart=/usr/local/bin/tailscale set --accept-dns=true
RemainAfterExit=true

[Install]
WantedBy=multi-user.target
```

Enabled on all 3 control planes via SSH.

### 5. Config change for future recreations

Added `extra_write_files` + `extra_runcmd` to the control_plane_nodepools in
`kube.tf`, mirroring the module's own pattern for `kh-annotate-node.service`
(`locals.tf:1512`): ship the `tailscale-accept-dns.service` unit above via
`extra_write_files`, then `systemctl daemon-reload` + `enable --now` it via
`extra_runcmd`.

An earlier version of this fix used only a bare `extra_runcmd` one-liner
(`tailscale set --accept-dns=true`) with no persistent unit. That only runs
once at cloud-init's first boot — it would not have survived a reboot on a
recreated node the way the systemd unit does on the currently-running
control planes, silently reopening the etcd peer TLS failure on the next
reboot/kured cycle with no runbook trigger. The write_files version closes
that gap: state now matches what's actually deployed on `iws`/`ugu`/`nbg`.

## Verification

```bash
# Routes advertised (from any tailscale node):
tails status --json | jq '.Peer[] | select(.HostName | test("control-plane")) | {HostName, PrimaryRoutes}'

# Home node routes installed:
ssh root@k3s-agent-hml.tail8255cc.ts.net 'ip route show table 52 | grep 10.255'

# Home node pods healthy:
kubectl get pods -A -o wide --field-selector spec.nodeName=k3s-agent-hml

# kubectl exec works (remotedialer):
kubectl exec -n kube-system kured-<pod> -- echo ok
```

## Rolling recreate — deferred

A rolling recreate (`tofu taint` + `tofu apply`) would bake
`advertise_node_private_routes = true` into the cloud-init permanently.
However, kube-hetzner does not preserve the public IPv4 on recreation (no
`primary_ipv4_id` configured), so the public IP and tailnet identity would
change, breaking the home node's connection until MagicDNS updates.

The systemd workaround handles the DNS issue on reboot, and the `extra_runcmd`
is in the state for future recreations. A clean recreate should be planned as
a maintenance window with coordinated home-node reconnection.

## Lessons learned

- kube-hetzner's `ignore_changes` on `user_data` means cloud-init changes
  require manual server recreation. Any tailscale config change (routes, tags,
  DNS) that goes through cloud-init needs `tofu taint` to take effect.
- The module hardcodes `--accept-dns=false`, which is incompatible with k3s
  etcd peer TLS. This is a module limitation, not a config error.
- Tailscale auto-approvers only apply on *first* route advertisement, not
  retroactively. After adding autoApprovers, re-advertise to trigger approval.
