output "server_id" {
  description = "Hetzner Cloud ID of the hermes server. Informational — use it with `hcloud server` commands or the API."
  value       = hcloud_server.hermes.id
  sensitive   = false
}

output "ipv4_address" {
  description = "Public IPv4 of the hermes server. Firewall-blocked and informational only: nothing should connect to it, all access is over the tailnet."
  value       = hcloud_server.hermes.ipv4_address
  sensitive   = false
}

output "tailscale_hostname" {
  description = "MagicDNS name of the hermes server — the SSH-over-tailnet target, e.g. `ssh hermes.tail1234.ts.net`. This is the only address worth using."
  value       = "${var.hermes_server_name}.${var.tailscale_magicdns_domain}"
  sensitive   = false
}

# Deliberately no `tailscale_ipv4` output. The 100.x address is assigned by
# Tailscale at boot, not by Hetzner, so Terraform never learns it. Read it from
# `tailscale status` (or use the MagicDNS name above, which is what the tailnet
# resolves to anyway) instead of inventing an attribute here.
