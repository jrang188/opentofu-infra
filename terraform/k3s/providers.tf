provider "hcloud" {
  # Ephemeral value from onepassword.tf: fetched fresh each phase, never
  # written to state. See onepassword.tf for why the module's own
  # hcloud_token *input variable* (kube.tf) still uses a plain data source.
  token = ephemeral.onepassword_item.hcloud_token.credential
}

# Pointed at the kube-hetzner module's structured kubeconfig output — the same
# reference the module's own providers-k8s.tf and its examples/argocd/main.tf
# use. `kubeconfig_data` is marked sensitive upstream; the provider's own
# fields are not, so the host and base64-decoded certs are visible in plan
# output. The host is a private Tailscale IP and state is local + unencrypted
# either way (TF_ENCRYPTION is the queued follow-up — see README "Operational
# notes"), so this is acceptable.
provider "kubernetes" {
  host                   = module.kube-hetzner.kubeconfig_data.host
  client_certificate     = module.kube-hetzner.kubeconfig_data.client_certificate
  client_key             = module.kube-hetzner.kubeconfig_data.client_key
  cluster_ca_certificate = module.kube-hetzner.kubeconfig_data.cluster_ca_certificate
}

# Empty on purpose: authenticates via the local `op` CLI session (must be
# signed in on the machine running tofu plan/apply). See onepassword.tf.
provider "onepassword" {
}
