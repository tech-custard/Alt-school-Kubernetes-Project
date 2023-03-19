terraform {
  required_providers {
    kubectl = {
      source  = "gavinbunney/kubectl"
      version = "1.14.0"
    }
  }
}

provider "aws" {
  region = var.region
}

provider "helm" {
  kubernetes {
    host                   = data.aws_eks_cluster.cluster.endpoint
    cluster_ca_certificate = base64decode(data.aws_eks_cluster.cluster.certificate_authority.0.data)
    token                  = data.aws_eks_cluster_auth.cluster.token
  }
}

provider "kubernetes" {
  host                   = data.aws_eks_cluster.cluster.endpoint
  cluster_ca_certificate = base64decode(data.aws_eks_cluster.cluster.certificate_authority.0.data)
  token                  = data.aws_eks_cluster_auth.cluster.token
}

provider "kubectl" {
  host                   = data.aws_eks_cluster.cluster.endpoint
  cluster_ca_certificate = base64decode(data.aws_eks_cluster.cluster.certificate_authority.0.data)
  token                  = data.aws_eks_cluster_auth.cluster.token
  load_config_file       = false
}


data "aws_availability_zones" "available" {}

data "aws_eks_cluster" "cluster" {
  name = module.eks.cluster_name
}

data "aws_eks_cluster_auth" "cluster" {
  name = module.eks.cluster_name
}

data "aws_iam_policy" "ebs_csi_policy" {
  arn = "arn:aws:iam::aws:policy/service-role/AmazonEBSCSIDriverPolicy"
}

data "kubernetes_service" "ingress_nginx" {
  metadata {
    name      = "ingress-nginx-controller"
    namespace = "default"
  }
  depends_on = [
    helm_release.ingress
  ]
}

# locals {
#   ingress_svc_name      = "ingress-nginx-controller"
#   ingress_svc_namespace = "default"
#   ingress_load_balancer_tags = {
#     "service.k8s.aws/resource" = "LoadBalancer"
#     "service.k8s.aws/stack"    = "${local.ingress_svc_namespace}/${local.ingress_svc_name}"
#     "elbv2.k8s.aws/cluster"    =  module.eks.cluster_endpoint
#   }
# }

# data "aws_lb" "nlb" {
#   tags = local.ingress_load_balancer_tags
# }
locals {
  lb_name_parts = split("-", split(".", data.kubernetes_service.ingress_nginx.status.0.load_balancer.0.ingress.0.hostname).0)
}

locals {
  name = join("-", slice(local.lb_name_parts, 0, length(local.lb_name_parts) - 1))
}

data "aws_elb" "nlb" {
  name = local.name
}

data "aws_iam_user" "example" {
  user_name = "altschool-user"
}

locals {
  cluster_name = "ms-eks-${random_string.suffix.result}"
}

resource "random_string" "suffix" {
  length  = 8
  special = false
}

#Provisioning VPC

module "vpc" {
  source  = "terraform-aws-modules/vpc/aws"
  version = "3.19.0"

  name = "ms-vpc"

  cidr = "10.0.0.0/16"
  azs  = slice(data.aws_availability_zones.available.names, 0, 3)

  private_subnets = ["10.0.1.0/24", "10.0.2.0/24", "10.0.3.0/24"]
  public_subnets  = ["10.0.4.0/24", "10.0.5.0/24", "10.0.6.0/24"]

  enable_nat_gateway   = true
  single_nat_gateway   = true
  enable_dns_hostnames = true

  public_subnet_tags = {
    "kubernetes.io/cluster/${local.cluster_name}" = "shared"
    "kubernetes.io/role/elb"                      = 1
  }

  private_subnet_tags = {
    "kubernetes.io/cluster/${local.cluster_name}" = "shared"
    "kubernetes.io/role/internal-elb"             = 1
  }
}

#Provisioning EKS
module "eks" {
  source  = "terraform-aws-modules/eks/aws"
  version = "~> 19.0"

  cluster_name    = local.cluster_name
  cluster_version = "1.24"

  cluster_endpoint_public_access = true

  vpc_id     = module.vpc.vpc_id
  subnet_ids = module.vpc.private_subnets

  cluster_addons = {
    coredns = {
      most_recent = true
    }
    kube-proxy = {
      most_recent = true
    }
    vpc-cni = {
      most_recent = true
    }
  }

  eks_managed_node_groups = {
    one = {
      name = "node-group-1"

      instance_types = ["c4.xlarge"]
      # instance_types = ["t2.medium"]

      min_size     = 1
      max_size     = 3
      desired_size = 1
    }
    # two = {
    #   name = "node-group-2"

    #   # instance_types = ["m4.xlarge"]
    #   instance_types = ["t2.medium"]
    #   min_size     = 1
    #   max_size     = 3
    #   desired_size = 1  
    # }
  }
}

# Provision EBS CSI DRIVER
module "irsa-ebs-csi" {
  source  = "terraform-aws-modules/iam/aws//modules/iam-assumable-role-with-oidc"
  version = "4.7.0"

  create_role                   = true
  role_name                     = "AmazonEKSTFEBSCSIRole-${data.aws_eks_cluster.cluster.name}"
  provider_url                  = replace(data.aws_eks_cluster.cluster.identity.0.oidc.0.issuer, "https://", "")
  role_policy_arns              = [data.aws_iam_policy.ebs_csi_policy.arn]
  oidc_fully_qualified_subjects = ["system:serviceaccount:kube-system:ebs-csi-controller-sa"]
}

resource "aws_eks_addon" "ebs-csi" {
  cluster_name             = data.aws_eks_cluster.cluster.name
  addon_name               = "aws-ebs-csi-driver"
  addon_version            = "v1.5.2-eksbuild.1"
  service_account_role_arn = module.irsa-ebs-csi.iam_role_arn
  tags = {
    "eks_addon" = "ebs-csi"
    "terraform" = "true"
  }
}
#Storage account
data "kubectl_path_documents" "gp3-sc" {
  pattern = "./files/gp3-sc.yaml"
}

resource "kubectl_manifest" "gp3-sc" {
  for_each  = toset(data.kubectl_path_documents.gp3-sc.documents)
  yaml_body = each.value
}
