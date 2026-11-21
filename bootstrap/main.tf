# Run once from your machine: the IAM role GitHub Actions assumes with OIDC to build and destroy the platform.
# It can only create IAM roles named eks-platform-*, attach the AWS-managed policies EKS needs, and manage the
# platform's network, cluster, load balancer, CloudFormation stack and CloudWatch resources.

terraform {
  required_version = ">= 1.10"
  required_providers {
    aws = { source = "hashicorp/aws", version = "~> 6.0" }
  }
}

provider "aws" {
  region = "us-east-1"
}

# Find yours with: gh api repos/OWNER/REPO/actions/oidc/customization/sub --jq .sub_claim_prefix
variable "github_sub_prefix" {
  type    = string
  default = "repo:dkojo@167027053/aws-eks-terraform@1466858727"
}

variable "state_bucket" {
  type    = string
  default = "danielkojomegbenu-tfstate"
}

data "aws_caller_identity" "me" {}
data "aws_iam_openid_connect_provider" "github" {
  url = "https://token.actions.githubusercontent.com"
}

locals {
  account = data.aws_caller_identity.me.account_id
  allowed_policies = [
    "arn:aws:iam::aws:policy/AmazonEKSClusterPolicy",
    "arn:aws:iam::aws:policy/AmazonEKSWorkerNodePolicy",
    "arn:aws:iam::aws:policy/AmazonEKS_CNI_Policy",
    "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly",
    "arn:aws:iam::aws:policy/CloudWatchAgentServerPolicy",
  ]
}

resource "aws_iam_role" "ci" {
  name = "github-eks-platform"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Action    = "sts:AssumeRoleWithWebIdentity"
      Principal = { Federated = data.aws_iam_openid_connect_provider.github.arn }
      Condition = {
        StringEquals = { "token.actions.githubusercontent.com:aud" = "sts.amazonaws.com" }
        StringLike   = { "token.actions.githubusercontent.com:sub" = ["${var.github_sub_prefix}:ref:refs/heads/main", "${var.github_sub_prefix}:pull_request"] }
      }
    }]
  })
}

resource "aws_iam_role_policy" "ci" {
  name = "build-eks-platform"
  role = aws_iam_role.ci.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid       = "PlatformServices"
        Effect    = "Allow"
        Action    = ["ec2:*", "elasticloadbalancing:*", "autoscaling:*", "eks:*", "cloudwatch:*", "logs:*"]
        Resource  = "*"
        Condition = { StringEquals = { "aws:RequestedRegion" = "us-east-1" } }
      },
      {
        Sid      = "OnlyThePlatformStack"
        Effect   = "Allow"
        Action   = "cloudformation:*"
        Resource = "arn:aws:cloudformation:us-east-1:${local.account}:stack/eks-platform-*"
      },
      { Sid = "ValidateTemplates", Effect = "Allow", Action = ["cloudformation:ValidateTemplate", "cloudformation:ListStacks"], Resource = "*" },
      {
        Sid    = "OnlyThePlatformRoles"
        Effect = "Allow"
        Action = ["iam:CreateRole", "iam:DeleteRole", "iam:GetRole", "iam:TagRole", "iam:UntagRole", "iam:ListRolePolicies",
        "iam:ListAttachedRolePolicies", "iam:ListInstanceProfilesForRole", "iam:PassRole", "iam:UpdateAssumeRolePolicy"]
        Resource = "arn:aws:iam::${local.account}:role/eks-platform-*"
      },
      {
        Sid       = "OnlyTheEksManagedPolicies"
        Effect    = "Allow"
        Action    = ["iam:AttachRolePolicy", "iam:DetachRolePolicy"]
        Resource  = "arn:aws:iam::${local.account}:role/eks-platform-*"
        Condition = { ArnEquals = { "iam:PolicyARN" = local.allowed_policies } }
      },
      { Sid = "ReadPolicies", Effect = "Allow", Action = ["iam:GetPolicy", "iam:GetPolicyVersion", "iam:GetOpenIDConnectProvider", "iam:ListOpenIDConnectProviders"], Resource = "*" },
      {
        Sid       = "ServiceLinkedRoles"
        Effect    = "Allow"
        Action    = "iam:CreateServiceLinkedRole"
        Resource  = "*"
        Condition = { StringLike = { "iam:AWSServiceName" = ["eks.amazonaws.com", "eks-nodegroup.amazonaws.com", "elasticloadbalancing.amazonaws.com", "autoscaling.amazonaws.com"] } }
      },
      { Sid = "StateBucket", Effect = "Allow", Action = "s3:ListBucket", Resource = "arn:aws:s3:::${var.state_bucket}" },
      { Sid = "StateObjects", Effect = "Allow", Action = ["s3:GetObject", "s3:PutObject", "s3:DeleteObject"], Resource = "arn:aws:s3:::${var.state_bucket}/aws-eks-terraform/*" },
    ]
  })
}

output "role_arn" { value = aws_iam_role.ci.arn }
