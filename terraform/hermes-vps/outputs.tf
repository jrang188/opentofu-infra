output "server_id" {
  description = "Hetzner server ID for this workspace."
  value       = hcloud_server.hermes.id
}

output "ipv4_address" {
  description = "Public IPv4. Nothing listens publicly: management access is over the tailnet, and the only open ports are ICMP and WireGuard for Tailscale."
  value       = hcloud_server.hermes.ipv4_address
}

output "tailscale_hostname" {
  description = "MagicDNS name the box claims on the tailnet (cloud-init --hostname). Resolve it from any tailnet device to reach the host without the public IP."
  value       = local.name
}

output "workspace" {
  description = "OpenTofu workspace backing this deployment. Each workspace is an independent server and an independent state file under terraform.tfstate.d/."
  value       = terraform.workspace
}

output "ssh_hint" {
  description = "How to reach the box. Public SSH is closed unless bootstrap_ssh_cidrs is set."
  value       = "ssh ${local.hermes_user}@${local.name}   # over the tailnet; the public IPv4 accepts no TCP/22"
}
