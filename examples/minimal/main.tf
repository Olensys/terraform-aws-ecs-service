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
  source = "git::https://github.com/Olensys/terraform-null-naming.git?ref=v1.0.0"

  context = local.context
}

locals {
  context = {
    organization = "olensys"
    environment  = "test"
    application  = "example"
    owner        = "platform"
    cost_center  = "eng"
  }
}

module "this" {
  source = "../../"

  name    = substr(module.naming.name, 0, 32)
  context = local.context
  tags    = module.naming.tags

  cluster_arn = var.cluster_arn
  network = {
    vpc_id     = var.vpc_id
    subnet_ids = var.subnet_ids
  }
  containers = {
    app = {
      # Containers must tolerate the module's read-only root filesystem; this image only sleeps.
      image   = "public.ecr.aws/amazonlinux/amazonlinux:2023"
      command = ["sleep", "infinity"]
    }
  }
}
