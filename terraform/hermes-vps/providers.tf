# Auth for hcloud comes from 1Password as an *ephemeral* value: fetched fresh
# each run, never written to state. Same pattern as terraform/k3s — see
# terraform/k3s/onepassword.tf for the full rationale.
#
# `provider "onepassword"` deliberately sets no token: it authenticates via the
# local `op` CLI session, so the machine running plan/apply must have `op`
# installed and signed in to the account below.
provider "hcloud" {
  token = ephemeral.onepassword_item.hcloud_token.credential
}

provider "onepassword" {
  account = "WAZ6QC3PINGPHPTDTK4UD6UGSI"
}
