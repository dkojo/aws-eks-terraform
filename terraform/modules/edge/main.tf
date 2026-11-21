# Layer 3: an Application Load Balancer in front of the node Auto Scaling group.
# Every node the ASG launches is registered with the target group automatically; the app listens on a NodePort.
variable "name" { type = string }
variable "vpc_id" { type = string }
variable "subnet_ids" { type = list(string) }
variable "asg_name" { type = string }
variable "node_sg_id" { type = string }
variable "app_node_port" { type = number }

resource "aws_security_group" "alb" {
  name   = "${var.name}-alb"
  vpc_id = var.vpc_id
  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

# Let the ALB reach the app's NodePort on the nodes
resource "aws_vpc_security_group_ingress_rule" "nodes_from_alb" {
  security_group_id            = var.node_sg_id
  referenced_security_group_id = aws_security_group.alb.id
  from_port                    = var.app_node_port
  to_port                      = var.app_node_port
  ip_protocol                  = "tcp"
}

resource "aws_lb" "this" {
  name               = var.name
  load_balancer_type = "application"
  security_groups    = [aws_security_group.alb.id]
  subnets            = var.subnet_ids
}

resource "aws_lb_target_group" "app" {
  name     = "${var.name}-app"
  port     = var.app_node_port
  protocol = "HTTP"
  vpc_id   = var.vpc_id
  health_check {
    path                = "/"
    healthy_threshold   = 2
    unhealthy_threshold = 2
    interval            = 10
    timeout             = 5
  }
}

resource "aws_lb_listener" "http" {
  load_balancer_arn = aws_lb.this.arn
  port              = 80
  protocol          = "HTTP"
  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.app.arn
  }
}

resource "aws_autoscaling_attachment" "nodes" {
  autoscaling_group_name = var.asg_name
  lb_target_group_arn    = aws_lb_target_group.app.arn
}

output "alb_dns_name" { value = aws_lb.this.dns_name }
output "alb_arn_suffix" { value = aws_lb.this.arn_suffix }
output "target_group_arn_suffix" { value = aws_lb_target_group.app.arn_suffix }
