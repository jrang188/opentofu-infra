terraform {
  required_version = "~> 1.12"

  required_providers {
    hcloud = {
      source = "hetznercloud/hcloud"
      # Major pin: block silent 2.x bumps.
      version = "~> 1.62"
    }
    onepassword = {
      source  = "1password/onepassword"
      version = "3.3.1"
    }
    # No kubernetes provider: this root never talks to the cluster.
  }
}
