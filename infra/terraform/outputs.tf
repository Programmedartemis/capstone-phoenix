output "control_plane_public_ip" {
  description = "Public IP address of the control-plane node"
  value       = module.compute.control_plane_public_ip
}

output "control_plane_private_ip" {
  description = "Private IP address of the control-plane node"
  value       = module.compute.control_plane_private_ip
}

output "worker_public_ips" {
  description = "Public IP addresses of the worker nodes"
  value       = module.compute.worker_public_ips
}

output "worker_private_ips" {
  description = "Private IP addresses of the worker nodes"
  value       = module.compute.worker_private_ips
}