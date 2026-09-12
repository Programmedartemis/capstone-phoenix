terraform {
  required_version = ">= 1.6.0"

  backend "s3" {
    bucket         = "phoenix-capstone-tfstate-11806"
    key            = "phoenix/terraform.tfstate"
    region         = "us-east-1"
    dynamodb_table = "phoenix-capstone-tf-lock"
    encrypt        = true
  }

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
  }
}

provider "aws" {
  region = var.aws_region
}