# opentofu-infra

OpenTofu configuration for personal infrastructure.

## `terraform/k3s` — Hetzner k3s cluster

A 3-node k3s cluster on Hetzner Cloud, built on
[kube-hetzner](https://github.com/kube-hetzner/terraform-hcloud-kube-hetzner)
v3.0.1.

| | |
|---|---|
| Nodes | 3 × `cx23` control planes in `fsn1`, workloads scheduled on them, no agent nodes |
| Management access | Tailscale node transport — public kube API and SSH are closed |
| Public ingress | Traefik behind Klipper LB, bound to each node's public IP on `:80`/`:443` |
| Storage | None. Hetzner CSI and Longhorn both disabled |
| Upgrades | k3s `stable` channel, unattended; Leap Micro transactional OS upgrades via kured |

Roughly €11.34/month for the three servers, excluding traffic and snapshots.

### Prerequisites

1. **OpenTofu `~> 1.12`** and **Packer**.
2. **Hetzner Cloud project** with a Read & Write API token.
3. **Tailscale account.** You need a **reusable, non-ephemeral** auth key —
   ephemeral keys reap nodes when they go offline, which is correct for
   autoscalers and wrong for static control planes. The machine running
   `tofu apply` must be logged in to the same Tailnet, because OpenTofu reaches
   the nodes over it.
4. **An SSH keypair.** Both the public and private key paths are passed to the
   module; they must be a matching pair.
5. **A Leap Micro snapshot in the Hetzner project.** The module looks it up by
   label and fails if it is missing:

   ```bash
   cd terraform/k3s/packer && packer build hcloud-leapmicro-snapshots.pkr.hcl
   ```

   Verify:

   ```bash
   hcloud image list --selector 'leapmicro-snapshot=yes,kube-hetzner/k8s-distro=k3s'
   ```

### Usage

```bash
cp terraform/k3s/terraform.tfvars.example terraform/k3s/terraform.tfvars
```

Fill in `tailscale_magicdns_domain` in `terraform.tfvars`. The Hetzner token,
Tailscale auth key, and SSH keys come from 1Password via the CLI, never from
disk. Create `terraform/k3s/.env.tofu` (gitignored) with secret references
pointing at your items:

```bash
TF_VAR_hcloud_token="op://Development/Hetzner Cloud API Token/token"
TF_VAR_tailscale_auth_key="op://Development/Tailscale/tailscale_auth_key"
TF_VAR_ssh_public_key="op://Development/SSH Key/public key"
TF_VAR_ssh_private_key="op://Development/SSH Key/private key"
```

Then run OpenTofu under `op run`, which resolves those references into
environment variables for the subprocess only. The Makefile in
`terraform/k3s/` wraps this (`make init`, `make plan`, `make apply`):

```bash
cd terraform/k3s
make init
make plan      # op run --env-file=.env.tofu -- tofu plan -out=k3s.tfplan
```

Review the plan, then apply the reviewed artifact (secrets are still needed for
the apply, so it runs under `op run` too):

```bash
make apply     # op run --env-file=.env.tofu -- tofu apply k3s.tfplan
```

SSH keys have a fallback: if you do not set `TF_VAR_ssh_*`, the config reads
`ssh_public_key_path` / `ssh_private_key_path` from disk (defaulting to
`~/.ssh/id_ed25519[.pub]`). The 1Password content wins when both are provided.

Retrieve the kubeconfig:

```bash
cd terraform/k3s && tofu output -raw kubeconfig > k3s_kubeconfig.yaml
```

```bash
KUBECONFIG=terraform/k3s/k3s_kubeconfig.yaml kubectl get nodes
```

Expect three `Ready` control-plane nodes.

### Teardown

```bash
cd terraform/k3s && make destroy   # plan -destroy -out=destroy.tfplan
```

Review what will be deleted, then `make apply-destroy` (apply is intentionally
not automatic). If the ingress load balancer detach races with the Hetzner CCM,
the upstream `scripts/destroy.sh` in the kube-hetzner repo handles that retry
and prints an orphan report.

### Development

Formatting, validation, linting, and a security scan run via
[pre-commit](https://pre-commit.com) on every commit:

```bash
pre-commit install
```

`terraform_fmt` and `terraform_validate` use whatever is already on `PATH`
(`tofu` and `terraform` both are). `terraform_tflint` and `terraform_trivy`
need their own binaries, not installed by pre-commit itself:

```bash
nix-env -iA nixpkgs.tflint nixpkgs.trivy
```

If you manage packages declaratively via home-manager, add `pkgs.tflint` and
`pkgs.trivy` to `home.packages` there instead — the command above is the
quick path.

Run against everything once, before the first real commit:

```bash
pre-commit run --all-files
```

`terraform_validate` does a real `tofu init` on first run — it needs network
access and is the slowest hook. Later runs reuse the cached `.terraform/`.

### Operational notes

- **State is local and unencrypted.** It contains the Tailscale auth key, the
  k3s cluster token, and the kubeconfig — all cluster-admin material. Consider
  [OpenTofu state encryption](https://opentofu.org/docs/language/state/encryption/),
  supplied via the `TF_ENCRYPTION` environment variable so no passphrase lands
  in the repo. Easiest to enable before the first apply.
- **Klipper on node IPs has no stable address.** Each node serves ingress on its
  own public IP, so replacing a node changes it. Fine while nothing public
  depends on the cluster; move to a Floating IP or a managed load balancer
  before pointing a real domain here.
- **`allow_scheduling_on_control_plane` must stay `true`.** With zero agent
  nodepools it is the only thing that lets workloads schedule at all.
- **Do not downgrade below module v3.0.1.** v3.0.0 fails later plans on
  zero-agent clusters (kube-hetzner#2236 / #2238).
- **Tailscale + CCM leaves nodes with the `node.cloudprovider.kubernetes.io/uninitialized`
  taint (module gap, unfixed through v3.1.0).** With `node_transport_mode = "tailscale"`
  and a single network, k3s registers nodes with private IPs (`10.255.0.x`) and no
  `node-external-ip`, so the Hetzner CCM cannot match them against the Hetzner API and
  never removes the uninitialized taint. All workload pods stay `Pending` and the
  `terraform_data.kustomization` remote-exec times out waiting on the
  system-upgrade-controller deployment. Manual fix:
  `kubectl taint nodes --all node.cloudprovider.kubernetes.io/uninitialized-`
  (must be repeated after any node reboot/kubelet restart). Root fix is to set
  `node-external-ip` on each control plane, but `control_planes_custom_config` cannot
  express per-node values — see the `node-untainter` DaemonSet experiment (removed) or
  wait for an upstream module fix. Full step-by-step:
  [`docs/runbooks/tailscale-ccm-uninitialized-taint.md`](docs/runbooks/tailscale-ccm-uninitialized-taint.md).
- **Simultaneous control-plane bootstrap can exceed the module's 360s join
  timeout**, failing `tofu apply` with exit 124 on `terraform_data.control_planes`
  even though k3s is actually healthy. See
  [`docs/runbooks/control-plane-join-timeout.md`](docs/runbooks/control-plane-join-timeout.md).
- `packer/hcloud-microos-snapshots.pkr.hcl` is unused — this cluster runs Leap
  Micro. It is kept only for reference.
