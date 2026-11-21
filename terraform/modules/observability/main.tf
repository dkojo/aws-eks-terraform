# Layer 5: observability. Container Insights on the cluster (an EKS add-on), and a CloudFormation stack
# with the CloudWatch dashboard and alarms, so the dashboards and alarms are reviewed as code too.
variable "name" { type = string }
variable "cluster_name" { type = string }
variable "alb_arn_suffix" { type = string }
variable "tg_arn_suffix" { type = string }
variable "asg_name" { type = string }

resource "aws_eks_addon" "container_insights" {
  cluster_name = var.cluster_name
  addon_name   = "amazon-cloudwatch-observability"
}

resource "aws_cloudformation_stack" "observability" {
  name          = "${var.name}-observability"
  template_body = file("${path.root}/../cloudformation/observability.yaml")
  parameters = {
    ClusterName  = var.cluster_name
    AlbArnSuffix = var.alb_arn_suffix
    TgArnSuffix  = var.tg_arn_suffix
    AsgName      = var.asg_name
  }
}

output "dashboard_name" { value = aws_cloudformation_stack.observability.outputs["DashboardName"] }
