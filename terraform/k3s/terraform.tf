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
  }
}
