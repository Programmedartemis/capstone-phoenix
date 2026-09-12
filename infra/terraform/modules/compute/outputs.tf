output "control_plane_public_ip" {
  description = "Public IP address of the control-plane node"
  value       = aws_instance.control_plane.public_ip
}

output "control_plane_private_ip" {
  description = "Private IP address of the control-plane node"
  value       = aws_instance.control_plane.private_ip
}

output "worker_public_ips" {
  description = "Public IP addresses of the worker nodes"
  value       = aws_instance.workers[*].public_ip
}

output "worker_private_ips" {
  description = "Private IP addresses of the worker nodes"
  value       = aws_instance.workers[*].private_ip
}