variable "aws_region" {
  description = "AWS region to deploy the infrastructure"
  type        = string
  default     = "us-east-1"
}

variable "project_name" {
  description = "Name used to identify project resources"
  type        = string
  default     = "phoenix-capstone"
}

variable "vpc_cidr" {
  description = "CIDR block for the VPC"
  type        = string
  default     = "172.31.0.0/16"
}

variable "public_subnet_cidr" {
  description = "CIDR block for the public subnet"
  type        = string
  default     = "172.31.1.0/24"
}

variable "instance_type" {
  description = "EC2 instance type for all nodes"
  type        = string
  default     = "t3.micro"
}

variable "control_plane_instance_type" {
  description = "EC2 instance type for the control-plane node"
  type        = string
  default     = "t3.small"
}

variable "worker_count" {
  description = "Number of worker nodes"
  type        = number
  default     = 2
}

variable "ssh_allowed_cidr" {
  description = "CIDR allowed to access SSH"
  type        = string
}

variable "key_name" {
  description = "Name of the AWS EC2 key pair"
  type        = string
  default     = "phoenix-capstone-key"
}