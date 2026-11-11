terraform {
  required_version = ">= 1.10.0"

  backend "s3" {
    bucket       = "devops-task-tfstate-33b24359cdc06619b607c93fe3"
    key          = "staging/terraform.tfstate"
    region       = "ap-southeast-1"
    encrypt      = true
    use_lockfile = true
  }

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.72"
    }
  }
}

provider "aws" {
  region = var.aws_region
}

module "runtime" {
  source = "../../modules/app-runtime"

  environment        = "staging"
  aws_region         = var.aws_region
  instance_type      = var.instance_type
  app_port           = var.app_port
  allowed_cidr       = var.allowed_cidr
  image_uri          = var.image_uri
  app_version        = var.app_version
  app_env            = "staging"
  log_level          = var.log_level
  log_retention_days = var.log_retention_days
}
