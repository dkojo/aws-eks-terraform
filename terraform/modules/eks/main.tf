# Layer 2: the EKS cluster and a managed node group (2 small nodes in an Auto Scaling group).
variable "name" { type = string }
variable "subnet_ids" { type = list(string) }

data "aws_iam_policy_document" "assume" {
  for_each = { cluster = "eks.amazonaws.com", node = "ec2.amazonaws.com" }
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = [each.value]
    }
  }
}

resource "aws_iam_role" "cluster" {
  name               = "${var.name}-cluster"
  assume_role_policy = data.aws_iam_policy_document.assume["cluster"].json
}

resource "aws_iam_role_policy_attachment" "cluster" {
  role       = aws_iam_role.cluster.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSClusterPolicy"
}

resource "aws_eks_cluster" "this" {
  name     = var.name
  version  = "1.37"
  role_arn = aws_iam_role.cluster.arn

  vpc_config {
    subnet_ids              = var.subnet_ids
    endpoint_public_access  = true
    endpoint_private_access = false
  }

  access_config {
    authentication_mode                         = "API"
    bootstrap_cluster_creator_admin_permissions = true # the pipeline's role can run kubectl
  }

  depends_on = [aws_iam_role_policy_attachment.cluster]
}

resource "aws_iam_role" "node" {
  name               = "${var.name}-node"
  assume_role_policy = data.aws_iam_policy_document.assume["node"].json
}

resource "aws_iam_role_policy_attachment" "node" {
  for_each = toset([
    "arn:aws:iam::aws:policy/AmazonEKSWorkerNodePolicy",
    "arn:aws:iam::aws:policy/AmazonEKS_CNI_Policy",
    "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly",
    "arn:aws:iam::aws:policy/CloudWatchAgentServerPolicy", # Container Insights
  ])
  role       = aws_iam_role.node.name
  policy_arn = each.value
}

resource "aws_eks_node_group" "this" {
  cluster_name    = aws_eks_cluster.this.name
  node_group_name = "${var.name}-nodes"
  node_role_arn   = aws_iam_role.node.arn
  subnet_ids      = var.subnet_ids
  ami_type        = "AL2023_x86_64_STANDARD"
  instance_types  = ["t3.small"]

  scaling_config {
    min_size     = 2
    desired_size = 2
    max_size     = 3
  }

  depends_on = [aws_iam_role_policy_attachment.node]
}

output "cluster_name" { value = aws_eks_cluster.this.name }
output "node_asg_name" { value = aws_eks_node_group.this.resources[0].autoscaling_groups[0].name }
output "node_security_group_id" { value = aws_eks_cluster.this.vpc_config[0].cluster_security_group_id }
