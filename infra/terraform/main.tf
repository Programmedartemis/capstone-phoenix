resource "aws_key_pair" "phoenix" {
  key_name   = var.key_name
  public_key = file("~/.ssh/phoenix-capstone.pub")
}

module "network" {
  source = "./modules/network"

  project_name       = var.project_name
  vpc_cidr           = var.vpc_cidr
  public_subnet_cidr = var.public_subnet_cidr
}

module "security_group" {
  source = "./modules/security_group"

  project_name     = var.project_name
  vpc_id           = module.network.vpc_id
  vpc_cidr         = var.vpc_cidr
  ssh_allowed_cidr = var.ssh_allowed_cidr
}

module "compute" {
  source = "./modules/compute"

  project_name                = var.project_name
  subnet_id                   = module.network.subnet_id
  security_group_id           = module.security_group.security_group_id
  instance_type               = var.instance_type
  control_plane_instance_type = var.control_plane_instance_type
  worker_count                = var.worker_count
  key_name                    = var.key_name
}