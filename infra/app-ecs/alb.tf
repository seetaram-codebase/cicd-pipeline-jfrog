# Stable public address for the demo app — same "the underlying compute
# can restart without changing the URL" reasoning as the Jenkins EC2's
# Elastic IP, but an ALB here since it also does the ECS target-group
# health checking / port routing to the single container instance.

resource "aws_lb" "app" {
  name               = "${var.app_name}-alb"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.alb.id]
  subnets            = data.aws_subnets.default.ids

  tags = { Name = "${var.app_name}-alb" }
}

# target_type = "instance" (not "ip") because the task runs in bridge
# network mode on a single EC2 container instance with a fixed host port
# — ECS registers/deregisters that instance:port with this target group
# automatically as the service starts/stops tasks.
resource "aws_lb_target_group" "app" {
  name        = "${var.app_name}-tg"
  port        = var.container_port
  protocol    = "HTTP"
  vpc_id      = data.aws_vpc.default.id
  target_type = "instance"

  health_check {
    path                = "/health"
    healthy_threshold   = 2
    unhealthy_threshold = 3
    interval            = 15
    timeout             = 5
    matcher             = "200"
  }

  tags = { Name = "${var.app_name}-tg" }
}

resource "aws_lb_listener" "http" {
  load_balancer_arn = aws_lb.app.arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.app.arn
  }
}
