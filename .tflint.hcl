config {
  # Default. Does not descend into the vendored kube-hetzner module — only
  # this repo's own root modules are linted.
  call_module_type = "local"
}

plugin "terraform" {
  enabled = true
  preset  = "recommended"
}
