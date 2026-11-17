# terraform/

## Responsibility

Namespace container for OpenTofu root modules. Holds two independent
roots: the k3s cluster (`k3s/`) and the standalone hermes-agent VM
(`hermes/`).

## Design

Each immediate subdir that contains a `*.tf` is a separate OpenTofu
root with its own state, init, plan, and apply cycle. Do not run
`tofu` commands from this folder — `tofu init` and friends must run
inside the subdir that owns the root module.

The two roots are deliberately independent: `hermes/` uses only
`hcloud` + `onepassword` and never reads the cluster's state or
kubeconfig, so either can be planned/applied without the other having
been applied first.

| Directory | Root module | Providers | State |
|---|---|---|---|
| `k3s/` | 3-node k3s cluster via `kube-hetzner` v3.0.1 | `hcloud`, `kubernetes`, `onepassword` | local, `k3s/terraform.tfstate` |
| `hermes/` | one tailnet-only VM for the hermes agent | `hcloud`, `onepassword` | local, `hermes/terraform.tfstate` |

## Flow

Not applicable — passthrough. See `terraform/k3s/codemap.md` and
`terraform/hermes/codemap.md` for the apply flows.

## Integration

Contains `terraform/k3s/` and `terraform/hermes/` (see their maps);
`terraform/k3s/packer/` is a Packer template subdir, not a root.
Pre-commit's `terraform_fmt` runs from the repo root and is recursive,
so it covers this folder — including `hermes/` — automatically.
