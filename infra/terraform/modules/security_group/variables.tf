variable "project_name" {
  description = "Name used to identify resources"
  type        = string
}

variable "vpc_id" {
  description = "ID of the VPC"
  type        = string
}

variable "vpc_cidr" {
  description = "CIDR block of the VPC"
  type        = string
}

variable "ssh_allowed_cidr" {
  description = "CIDR allowed to access SSH"
  type        = string
}