# terraform/k3s/packer/

## Responsibility

Packer templates that build the Hetzner Cloud snapshot the `kube-hetzner`
module in the parent dir requires. The module looks the snapshot up by
label at apply time and fails if it is missing, so this folder is a
real prerequisite, not an optional extra.

## Design

Two templates live here, but only one is wired in:

- `hcloud-leapmicro-snapshots.pkr.hcl` — **used**. Builds a Leap Micro
  6.2 snapshot (the default) for x86 (`cx23` / `nbg1`) and arm
  (`cax11` / `fsn1`). Reads `HCLOUD_TOKEN` from the env, **not**
  `TF_VAR_hcloud_token`.
- `hcloud-microos-snapshots.pkr.hcl` — **reference only**. This cluster
  runs Leap Micro, not MicroOS. Kept for context; do not modify or wire
  it up.

The module's snapshot lookup is hard-coded to these labels:

- `leapmicro-snapshot=yes`
- `kube-hetzner/k8s-distro=k3s`

Both must be present on the produced image or the next `tofu apply`
fails to find it.

## Flow

1. `cd terraform/k3s/packer && packer build hcloud-leapmicro-snapshots.pkr.hcl`
2. Packer boots a throwaway server per architecture, installs Leap
   Micro 6.2, snapshots it, and tags the resulting Hetzner image.
3. Verify with
   `hcloud image list --selector 'leapmicro-snapshot=yes,kube-hetzner/k8s-distro=k3s'`.

Server type and location defaults are overridable for projects where
they are unavailable:

```
packer build -var x86_server_type=cpx31 -var x86_location=fsn1 \
  hcloud-leapmicro-snapshots.pkr.hcl
```

Build only one architecture with `-only=<source_name>` when the other
is out of capacity. Disk must be ≥ 40 GiB.

## Integration

- Pure consumer of `HCLOUD_TOKEN`; producer of the Hetzner image the
  cluster module in `terraform/k3s/` reads at apply time.
- Pre-commit's `terraform_fmt` runs recursively from the repo root and
  will also touch this folder even though it is HCL, not `.tf`.
