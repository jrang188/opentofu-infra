# Control plane join times out during simultaneous bootstrap

## Symptom

`tofu apply` fails with something like:

```
Error: remote-exec provisioner error

  with module.kube-hetzner.terraform_data.control_planes["0-1-control-plane"],
  on .terraform/modules/kube-hetzner/control_planes.tf line 783, in resource "terraform_data" "control_planes":
 783:   provisioner "remote-exec" {

error executing "/tmp/terraform_XXXXXXXX.sh": Process exited with status 124
```

on one or more **non-first** control planes (the first control plane is
provisioned by a separate resource and isn't affected by this).

## Root cause

The module's post-install step polls, for up to 360 seconds:

```bash
until systemctl status k3s > /dev/null; do
  systemctl start k3s 2> /dev/null
  sleep 3
done
```

(`control_planes.tf:783`, second `remote-exec` block). Exit 124 means the
`timeout 360` wrapper killed the loop, not that k3s failed.

When multiple control planes bootstrap etcd at nearly the same time — e.g.
right after a full destroy/recreate where all 3 come up together — joining
as the 2nd/3rd etcd member can legitimately take longer than 360 seconds.
Any added boot-time delay (Tailscale tag advertisement, route setup, etc.)
eats into that same window. **This is a fixed-timeout race, not a real
provisioning failure.**

## How to tell it's this, not a real failure

SSH to the affected node over Tailscale and check:

```bash
systemctl status k3s
journalctl -u k3s -n 200 --no-pager
```

If `k3s` is active and the log shows normal steady-state activity (etcd
compaction, API server handling requests) rather than crash-looping or
connection errors, it's this race — k3s came up, just not within the
module's fixed window.

You will very likely also be hitting
[the Tailscale CCM uninitialized-taint runbook](tailscale-ccm-uninitialized-taint.md)
at the same time — the k3s log spamming
`"waiting for removal of node.cloudprovider.kubernetes.io/uninitialized taint"`
is expected and is a separate issue, not a sign that this node also failed.

## Fix

1. Confirm k3s is healthy on the affected node (above).
2. Retry: `make plan && make apply`. Terraform will recreate only the
   tainted `terraform_data.control_planes` resource(s) and re-run their
   provisioners against the already-running k3s service — the
   `systemctl status k3s` check should now pass almost instantly.
3. If the retry also times out waiting on `system-upgrade-controller`, that's
   the separate CCM taint issue — go clear the taint, see the linked runbook.
