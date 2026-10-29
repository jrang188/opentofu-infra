# `terraform/hermes-vps` — single Ubuntu VPS for the Hermes gateway

One always-on Hetzner box that runs the messaging gateway natively and nothing
else. No Kubernetes, no containers, no ingress. Management access is over the
tailnet; the public IPv4 accepts ICMP and WireGuard only.

This root is independent of `terraform/k3s`: separate directory, separate
state, separate lifetime. The cluster is not mutated, imported, or referenced.

| | |
|---|---|
| Server | 1 × `cx33` (4 vCPU / 8 GB / 80 GB) in `fsn1`, Ubuntu 24.04 LTS |
| Access | Tailscale only. Public SSH closed unless `bootstrap_ssh_cidrs` is set |
| Firewall | Hetzner: ICMP + UDP/41641 (Tailscale WireGuard). Host: ufw, default-deny |
| State | Local, **encrypted** (OpenTofu `encryption` block), one file per workspace |
| Cost | ~€6.99/month (€6.49 server + €0.50 IPv4) |

## Prerequisites

1. **OpenTofu `~> 1.12`** and the `op` CLI signed in to the configured account —
   the same two requirements as `terraform/k3s` (see the repo `README` and
   `AGENTS.md`).
2. **1Password items** in the `Development` vault: `hetzner-cloud-api-token`,
   `ssh-key`, `tailscale-auth-key`. The tailnet key must be **reusable and
   non-ephemeral**, exactly as for `terraform/k3s`.
3. **A state passphrase** in 1Password at
   `op://Development/tofu-state/hermes-vps-passphrase`. There is no default.
   Losing it makes this root's state unreadable — recoverable by
   re-provisioning, but not free.

## Usage

The OpenTofu workspace **is** the deployment name, so two environments are two
workspaces, not two copies of this directory.

```bash
cd terraform/hermes-vps

source env.sh                      # exports TF_ENCRYPTION from 1Password
tofu init
tofu workspace new hermes-vps     # creates terraform.tfstate.d/hermes-vps/
tofu plan                          # no -var needed; workspace selects the name
tofu apply
```

`env.sh` is what turns on state encryption (see `terraform.tf` for why it is an
environment variable rather than an in-file `encryption` block). Skip it and
OpenTofu refuses to read the encrypted state — it fails closed rather than
writing plaintext, so a forgotten `source` is an error, never a downgrade.

The `default` workspace is refused by a `precondition` on the server resource:
planning there would create a host called `default` whose state nobody accounts
for.

Teardown is `tofu destroy` from the same workspace. Do not destroy while the
gateway is holding state you have not restored elsewhere.

## What cloud-init does (and does not do)

First boot, once:

- creates the unprivileged `hermes` user with `HOME=/opt/data/home`, no sudo,
  key-only SSH; refuses password and root login
- creates `/opt/data` owned by `hermes`, because `HERMES_HOME=/opt/data` is
  preserved from the container layout — thousands of absolute paths in skills,
  scripts and cron jobs resolve only if this shape matches
- installs Tailscale from its apt repo and joins the tailnet under the workspace
  name (`--hostname`), **without** Tailscale SSH
- 2 GB swapfile, `vm.swappiness=10`
- ufw: default deny inbound, trusted `tailscale0`, UDP/41641 open for the direct
  Tailscale path
- security-only unattended upgrades; **release upgrades stay manual**

It does **not** install Hermes, provision R2, or touch anything in the homelab.
Installing the gateway is a reviewed, documented step; keeping it out of
cloud-init means a rebuild cannot silently change the runtime the agent depends
on.

`user_data` is `ignore_changes`d: cloud-init runs once, so editing the template
would otherwise plan a destroy/recreate of a server holding live state. Bootstrap
changes to a running host are made by hand and recorded in the runbook;
replacing the VPS is a decision, not a side effect.

## Recovery

- **Locked out of the tailnet?** Hetzner's web console bypasses the firewall —
  use it, fix `/var/log/cloud-init-output.log`, re-run
  `/usr/local/sbin/hermes-firstboot` (idempotent).
- **Need temporary public SSH?** `-var 'bootstrap_ssh_cidrs=["<your-ip>/32"]'`,
  apply, fix, then apply again with the default empty list. The firewall rule
  and the ufw rule are both conditional on that variable, so removing it removes
  both.
- **Lost the state passphrase?** The server can be re-created from code. State
  history is gone; that is the trade for having state encrypted.

## Scope boundary

Deliberately not in this root: the R2 backup bucket, DNS, the gateway install,
and anything inside the homelab. Those are separate changes with separate blast
radii.
