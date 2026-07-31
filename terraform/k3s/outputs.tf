output "control_planes_public_ipv4" {
  description = "Public IPv4 address of each control plane. These are the addresses Klipper serves :80/:443 on."
  value       = module.kube-hetzner.control_planes_public_ipv4
}

output "kubeconfig" {
  description = "Cluster kubeconfig. Extract with: tofu output -raw kubeconfig > k3s_kubeconfig.yaml"
  value       = module.kube-hetzner.kubeconfig
  sensitive   = true
}
