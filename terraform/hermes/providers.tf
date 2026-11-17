provider "hcloud" {
  # Ephemeral — never written to state.
  token = ephemeral.onepassword_item.hcloud_token.credential
}

provider "onepassword" {
  account = "WAZ6QC3PINGPHPTDTK4UD6UGSI"
}
