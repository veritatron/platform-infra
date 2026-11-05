output "server_name" {
  description = "Name of the control plane server."
  value       = hcloud_server.control_plane.name
}

output "server_ipv4" {
  description = "Public IPv4 address (Primary IP) of the control plane server."
  value       = hcloud_primary_ip.control_plane.ip_address
}

output "ssh_command" {
  description = "SSH command for the control plane server."
  value       = "ssh root@${hcloud_primary_ip.control_plane.ip_address}"
}

output "kube_api_url" {
  description = "URL of the Kubernetes API."
  value       = "https://${hcloud_primary_ip.control_plane.ip_address}:${local.ports.kube_api}"
}
