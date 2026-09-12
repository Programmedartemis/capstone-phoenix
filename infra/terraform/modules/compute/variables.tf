variable "project_name" {
  description = "Name used to identify resources"
  type        = string
}

variable "subnet_id" {
  description = "ID of the subnet where the instances will run"
  type        = string
}

variable "security_group_id" {
  description = "Security group ID for the instances"
  type        = string
}

variable "instance_type" {
  description = "EC2 instance type"
  type        = string
}

variable "worker_count" {
  description = "Number of worker nodes"
  type        = number
}

variable "key_name" {
  description = "AWS key pair name used for SSH"
  type        = string
}

variable "control_plane_instance_type" {
  description = "EC2 instance type for the control-plane node"
  type        = string
  default     = "t3.small"
}