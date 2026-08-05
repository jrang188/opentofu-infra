# terraform/

## Responsibility

Namespace container for OpenTofu root modules. Currently holds only
the k3s cluster.

## Design

Each immediate subdir that contains a `*.tf` is a separate OpenTofu
root with its own state, init, plan, and apply cycle. Do not run
`tofu` commands from this folder — `tofu init` and friends must run
inside the subdir that owns the root module.

## Flow

Not applicable — passthrough. See `terraform/k3s/codemap.md` for the
apply flow.

## Integration

Contains `terraform/k3s/` (see its map). Pre-commit's
`terraform_fmt` runs from the repo root and is recursive, so it
covers this folder automatically.
