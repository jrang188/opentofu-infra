# `terraform/hermes-vps` — single Ubuntu VPS for the Hermes gateway

One always-on Hetzner box that runs the messaging gateway natively and nothing
else. No Kubernetes, no containers, no ingress service. Management access is
over the tailnet; the public IPv4 accepts ICMP and WireGuard only.

This root is independent of `terraform/k3s`: separate directory, separate
state, separate lifetime. The cluster is not mutated, imported, or referenced.

| | |
|---|---|
| Server | 1 × `cx33` (4 vCPU / 8 GB / 80 GB) in `fsn1`, Ubuntu 24.04 LTS |
| Access | Tailscale only. Public SSH closed by default (see Recovery) |
| Firewall | Hetzner: ICMP + UDP/41641 (Tailscale WireGuard). Host: ufw, default-deny |
| State | Local, **encrypted** via `TF_ENCRYPTION`, one file per workspace |
| Destroy safety | `prevent_destroy` + Hetzner `delete_protection` on the server |
| Cost | ~€6.99/month (€6.49 server + €0.50 IPv4) |

## Prerequisites

1. **OpenTofu `~> 1.12`** and the `op` CLI signed in to the configured account —
   the same two requirements as `terraform/k3s` (see the repo `README` and
   `AGENTS.md`).
2. **1Password items** in the `Development` vault:
   `hetzner-cloud-api-token`, `ssh-key` (the agent reads only its `public key`
   field), `tailscale-auth-key`.
3. The tailnet key should be **single-use and pre-authorised** rather than
   reusable: cloud-init consumes it once and shreds its own copy. Revoke it in
   the Tailscale admin console after first boot. (The `k3s` root needs a
   reusable, non-ephemeral key because its nodes enrol repeatedly; a one-shot VPS
   does not.)
4. **A state passphrase** in 1Password at
   `op://Development/tofu-state/hermes-vps-passphrase` — 16+ characters from a
   base64/hex-safe alphabet (no quotes, backslashes, `${`, `%{` or newlines).
   `env.sh` refuses anything else rather than trying to escape it. Losing the
   passphrase makes this root's state unreadable.

## Usage

The OpenTofu workspace **is** the deployment name, so two environments are two
workspaces, not two copies of this directory.

```bash
cd terraform/hermes-vps

source env.sh                      # TF_ENCRYPTION + TF_VAR_ssh_public_key
tofu init
tofu workspace new hermes-vps      # creates terraform.tfstate.d/hermes-vps/
tofu plan                          # workspace name selects the deployment name
tofu apply
```

`env.sh` supplies two things that must not live in the repo or in a plain data
source: the state-encryption passphrase, and the SSH **public** key (an
`onepassword_item` data source would persist the item's private key into state).

Encryption caveat, stated plainly: because the key material arrives by
environment variable, a **fresh** workspace with no `env.sh` would write
plaintext state. `terraform_data.encryption_guard` closes that for `apply` — it
runs first and aborts the run — but `tofu plan -out=FILE` without `env.sh` still
writes an unencrypted plan file. Don't use `-out` without sourcing `env.sh`.

The `default` workspace is refused by a `precondition` on the server resource:
planning there would create a host called `default` whose state nobody accounts
for.

## Destroying is deliberately two steps

Destroying this root deletes the server and therefore the disk holding
`HERMES_HOME`. Two protections stand in the way and both must be removed
deliberately:

1. `lifecycle.prevent_destroy` on the server and the firewall
2. `delete_protection = true` on the server, enforced by the Hetzner API

`tofu destroy` will fail until you remove them. That is the point: decommission
is a reviewed sequence (restore verified elsewhere, state archived, then
teardown), not a command.

## What cloud-init does (and does not do)

First boot, once, in this order:

1. **Local** — creates the unprivileged `hermes` user (`HOME=/opt/data/home`, no
   sudo, key-only), `/opt/data` owned by it (`HERMES_HOME=/opt/data` is preserved
   from the container layout, and thousands of absolute paths depend on it),
   a 2 GB swapfile with `swappiness=10`, then restarts sshd with the hardening
   drop-in (no password auth, no root login, `AllowUsers hermes`).
2. **Network, retried** — Tailscale from its apt repo (`--retry`/`Acquire::Retries`),
   then up to five attempts to join the tailnet as `--hostname=<workspace>`,
   **without** Tailscale SSH. On success the staged key at
   `/root/.tailscale-authkey` is shredded.
3. **Last** — ufw: default deny inbound, trusted `tailscale0`, UDP/41641 open for
   the direct path. Enabled only after the join, so a failed join leaves no open
   ports rather than a half-hardened host.

It does **not** install Hermes, provision R2, or touch the homelab. Keeping the
runtime out of cloud-init means a rebuild cannot silently change what the agent
depends on.

`user_data` is `ignore_changes`d: cloud-init runs once, so editing the template
would otherwise plan a destroy/recreate of a server holding live state.

### Apply success is not host readiness

OpenTofu waits for Hetzner's server actions, not for cloud-init. A failed join
leaves a running, billable, unreachable host. Before trusting a deployment:

```bash
ssh hermes@hermes-vps 'cat /var/lib/hermes-firstboot.status'
# expect a final line: complete <timestamp>
```

### Secret exposure you should know about

The tailnet enrollment key is staged in a `0600` root-only file and shredded
after the join, and the bootstrap script is `0700`. It is still present in
cloud-init `user_data`, which the instance metadata service serves to anyone
with local access (including the `hermes` user) for the life of the server. That
is why the key should be single-use and revoked after first boot; a reusable key
in `user_data` is a durable tailnet-enrollment capability handed to the agent.

## Recovery

- **Locked out of the tailnet?** Use Hetzner's **console** (it bypasses the
  firewall) or, better, the **rescue system**: enable rescue in the Hetzner
  console, reboot into it, and you get a root shell with a generated password.
  `hermes` has no password and no sudo, and `disable_root: true` means the
  console cannot log in as root directly.
- **Then** read `/var/lib/hermes-firstboot.status` and
  `/var/log/cloud-init-output.log`, replace `/root/.tailscale-authkey` with a
  fresh key, and re-run `/usr/local/sbin/hermes-firstboot` (idempotent — but it
  resets ufw, so hand-added rules must be re-added).
- **Need temporary public SSH?** Two separate things must open, and only one is
  managed here:
  1. `-var 'bootstrap_ssh_cidrs=["<your-ip>/32"]'` + apply → **Hetzner** firewall
     rule (cloud-init does not re-run, so this does not touch ufw).
  2. On the host: `ufw allow from <your-ip>/32 to any port 22 proto tcp`.
  Reverse both when done: apply with the default empty list, and
  `ufw delete allow from <your-ip>/32 to any port 22 proto tcp`.
- **Lost the state passphrase?** The server can be re-created from code; the
  state history is gone. That is the trade for encrypted state.

## Scope boundary

Deliberately not in this root: the R2 backup bucket, DNS, the gateway install,
and anything inside the homelab. Those are separate changes with separate blast
radii.
