terraform {
  # Pinned to the current minor. The kube-hetzner module floor is >= 1.10.1;
  # this is tighter so a runtime upgrade is a deliberate, reviewable change.
  required_version = "~> 1.12"

  required_providers {
    hcloud = {
      source = "hetznercloud/hcloud"
      # Major pin rather than the module's open-ended >= 1.62.0, so a breaking
      # 2.x release cannot be picked up silently. Currently locked at 1.68.0
      # in .terraform.lock.hcl — commit that file.
      version = "~> 1.62"
    }
    kubernetes = {
      source = "hashicorp/kubernetes"
      # Major pin to match the hcloud pattern. The kube-hetzner module already
      # requires >= 3.1.0 (locked at 3.2.1 in .terraform.lock.hcl), so this
      # just widens nothing and blocks a future 4.x release from being picked
      # up silently. Commit the lockfile after `make init`.
      version = "~> 3.1"
    }
  }
}
