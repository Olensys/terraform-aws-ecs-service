terraform {
  required_version = ">= 1.5.0"

  required_providers {
    aws = { source = "hashicorp/aws", version = ">= 6.0, < 7.0" }
  }
}

variable "cluster_arn" {
  description = "ARN of an existing ECS cluster."
  type        = string
}

variable "vpc_id" {
  description = "VPC the service runs in."
  type        = string
}

variable "subnet_ids" {
  description = "Subnets for the tasks."
  type        = list(string)
}

module "naming" {
  source = "git::https://github.com/Olensys/terraform-null-naming.git?ref=v1.0.1"

  context = local.context
}

locals {
  context = {
    organization = "olensys"
    environment  = "test"
    application  = "ecssvc"
    owner        = "platform"
    cost_center  = "eng"
  }
}

module "this" {
  source = "../../"

  name    = substr(module.naming.name, 0, 32)
  context = local.context
  tags    = module.naming.tags

  cpu    = 256
  memory = 512

  cluster_arn = var.cluster_arn
  network = {
    vpc_id     = var.vpc_id
    subnet_ids = var.subnet_ids
    # the shared test VPC has no NAT gateway; tasks need a public IP to pull the image
    assign_public_ip = true
  }
  containers = {
    app = {
      # Containers must tolerate the module's read-only root filesystem; this image only sleeps.
      image   = "public.ecr.aws/amazonlinux/amazonlinux:2023"
      command = ["sleep", "infinity"]
    }
  }
}
