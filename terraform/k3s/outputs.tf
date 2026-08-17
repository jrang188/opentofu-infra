output "control_planes_public_ipv4" {
  description = "Public IPv4 address of each control plane. These are the addresses Klipper serves :80/:443 on."
  value       = module.kube-hetzner.control_planes_public_ipv4
}

output "ingress_floating_ipv4" {
  description = "Stable public IPv4 for the Klipper ingress path. Point external-dns (homelab-k8s infra/external-dns, jrang188/homelab-k8s#9) at this instead of any single node's own address."
  value       = hcloud_floating_ip.ingress.ip_address
}

output "kubeconfig" {
  description = "Cluster kubeconfig. Extract with: tofu output -raw kubeconfig > k3s_kubeconfig.yaml"
  value       = module.kube-hetzner.kubeconfig
  sensitive   = true
}
