# Fargate tasks get a new public IP every restart, which breaks the Jenkins
# UI, the build agent's connect command, and (fatally) the GitHub webhook
# every single time. This puts a stable DNS name in front of it so nothing
# downstream has to track a moving target again.

resource "aws_security_group" "alb" {
  name        = "${var.app_name}-alb-sg"
  description = "Jenkins ALB"
  vpc_id      = data.aws_vpc.default.id

  ingress {
    description = "Jenkins web UI / webhook / agent WebSocket"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = [var.admin_cidr]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = { Name = "${var.app_name}-alb-sg" }
}

resource "aws_lb" "jenkins" {
  name               = "${var.app_name}-alb"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.alb.id]
  subnets            = data.aws_subnets.default.ids

  tags = { Name = "${var.app_name}-alb" }
}

resource "aws_lb_target_group" "jenkins" {
  name        = "${var.app_name}-tg"
  port        = 8080
  protocol    = "HTTP"
  vpc_id      = data.aws_vpc.default.id
  target_type = "ip"

  health_check {
    path                = "/login"
    interval            = 30
    timeout             = 10
    healthy_threshold   = 2
    unhealthy_threshold = 5
  }

  tags = { Name = "${var.app_name}-tg" }
}

resource "aws_lb_listener" "jenkins" {
  load_balancer_arn = aws_lb.jenkins.arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.jenkins.arn
  }
}
