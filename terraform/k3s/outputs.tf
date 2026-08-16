output "control_planes_public_ipv4" {
  description = "Public IPv4 address of each control plane. These are the addresses Klipper serves :80/:443 on."
  value       = module.kube-hetzner.control_planes_public_ipv4
}

# kube-hetzner creates the floating IP itself (kube.tf's
# control_plane_nodepools[0].nodes["0"].floating_ip) but doesn't output its
# address, so it's looked up here by the label the module puts on every
# floating IP it manages (locals.tf: cluster = var.cluster_name).
data "hcloud_floating_ips" "control_plane" {
  with_selector = "cluster=${var.cluster_name}"
}

output "ingress_floating_ipv4" {
  description = "Stable public IPv4 for the Klipper ingress path. Point external-dns (homelab-k8s infra/external-dns, jrang188/homelab-k8s#9) at this instead of any single node's own address. Null until the first apply that creates the floating IP has completed — the data source can't see a resource created in the same apply."
  value       = try(one(data.hcloud_floating_ips.control_plane.floating_ips).ip_address, null)
}

output "kubeconfig" {
  description = "Cluster kubeconfig. Extract with: tofu output -raw kubeconfig > k3s_kubeconfig.yaml"
  value       = module.kube-hetzner.kubeconfig
  sensitive   = true
}
