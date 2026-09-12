output "security_group_id" {
  description = "ID of the Phoenix capstone security group"
  value       = aws_security_group.this.id
}