provider "hcloud" {
  token = var.hcloud_token
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
