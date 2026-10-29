terraform {
  # Same pin as terraform/k3s: the toolchain is deliberately narrow so a
  # runtime upgrade is a reviewable change, not a surprise.
  required_version = "~> 1.12"

  required_providers {
    hcloud = {
      source = "hetznercloud/hcloud"
      # Major pin to match the k3s root — a breaking 2.x must not be picked
      # up silently by this root either. Lockfile is committed.
      version = "~> 1.62"
    }
    onepassword = {
      source  = "1password/onepassword"
      version = "3.3.1"
    }
  }

  # State encryption (OpenTofu >= 1.10) is configured through the
  # TF_ENCRYPTION environment variable rather than an in-file `encryption`
  # block. Two reasons:
  #
  #   1. An in-file block that references the passphrase is evaluated during
  #      `tofu init`, which makes the secret a hard requirement for
  #      `tofu validate` and for the pre-commit `terraform_validate` hook —
  #      i.e. it breaks the repo's CI path for every fresh clone.
  #   2. It is fail-closed: OpenTofu refuses to read an encrypted state
  #      without the configuration ("This state file is encrypted and can not
  #      be read without an encryption configuration"), so forgetting the
  #      export produces an error, never a plaintext rewrite.
  #
  # Use `source env.sh` in this directory before any state operation. The k3s
  # root is queued to adopt the same mechanism (AGENTS.md "Secrets and state"),
  # so the two roots converge rather than diverge.
}
