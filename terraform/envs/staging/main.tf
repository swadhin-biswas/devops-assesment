terraform {
  required_version = ">= 1.10.0"

  backend "s3" {}

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.72"
    }
  }
}

provider "aws" {
  region = var.aws_region

  default_tags {
    tags = {
      Project   = "devops-task"
      ManagedBy = "terraform"
    }
  }
}

locals {
  # The image tag is the single source of truth for the version. A pinned
  # vMAJOR.MINOR.PATCH tag means the container reports the version that is
  # actually running, so the value cannot drift away from the tag.
  image_tag   = split(":", var.image_uri)[1]
  app_version = trimprefix(local.image_tag, "v")
}

module "runtime" {
  source = "../../modules/app-runtime"

  environment        = "staging"
  aws_region         = var.aws_region
  instance_type      = var.instance_type
  app_port           = var.app_port
  allowed_cidr       = var.allowed_cidr
  image_uri          = var.image_uri
  app_version        = local.app_version
  app_env            = "staging"
  log_level          = var.log_level
  log_retention_days = var.log_retention_days
}
