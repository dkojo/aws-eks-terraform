# The platform, built in layers. Each layer is a module, and the pipeline applies them bottom-up:
#   1 network  ->  2 eks  ->  3 edge (load balancer on the nodes' Auto Scaling group)  ->  4 workloads (kubectl)  ->  5 observability
# and destroys everything at the end of the run.

terraform {
  required_version = ">= 1.10"
  required_providers {
    aws = { source = "hashicorp/aws", version = "~> 6.0" }
  }
  backend "s3" {
    bucket       = "danielkojomegbenu-tfstate"
    key          = "aws-eks-terraform/terraform.tfstate"
    region       = "us-east-1"
    use_lockfile = true
  }
}

provider "aws" {
  region = "us-east-1"
  default_tags {
    tags = { Project = "aws-eks-terraform", ManagedBy = "terraform" }
  }
}

locals {
  name = "eks-platform"
}

module "network" {
  source = "./modules/network"
  name   = local.name
}

module "eks" {
  source     = "./modules/eks"
  name       = local.name
  subnet_ids = module.network.public_subnet_ids
}

module "edge" {
  source        = "./modules/edge"
  name          = local.name
  vpc_id        = module.network.vpc_id
  subnet_ids    = module.network.public_subnet_ids
  asg_name      = module.eks.node_asg_name
  node_sg_id    = module.eks.node_security_group_id
  app_node_port = 30080
}

module "observability" {
  source         = "./modules/observability"
  name           = local.name
  cluster_name   = module.eks.cluster_name
  alb_arn_suffix = module.edge.alb_arn_suffix
  tg_arn_suffix  = module.edge.target_group_arn_suffix
  asg_name       = module.eks.node_asg_name
}

output "cluster_name" { value = module.eks.cluster_name }
output "asg_name" { value = module.eks.node_asg_name }
output "app_url" { value = "http://${module.edge.alb_dns_name}" }
output "dashboard" { value = module.observability.dashboard_name }
