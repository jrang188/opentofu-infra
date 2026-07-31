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

Fill in `tailscale_magicdns_domain` and your SSH key paths, then export the
secrets rather than writing them to disk:

```bash
export TF_VAR_hcloud_token=... TF_VAR_tailscale_auth_key=...
```

```bash
cd terraform/k3s && tofu init && tofu plan -out=k3s.tfplan
```

Review the plan, then apply the reviewed artifact:

```bash
tofu apply k3s.tfplan
```

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
cd terraform/k3s && tofu plan -destroy -out=destroy.tfplan
```

Review what will be deleted, then `tofu apply destroy.tfplan`. If the ingress
load balancer detach races with the Hetzner CCM, the upstream
`scripts/destroy.sh` in the kube-hetzner repo handles that retry and prints an
orphan report.

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
- `packer/hcloud-microos-snapshots.pkr.hcl` is unused — this cluster runs Leap
  Micro. It is kept only for reference.
