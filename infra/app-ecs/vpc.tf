# Default VPC, same pattern as infra/jenkins-ecs — simplest setup for a
# time-boxed demo, not a production security posture.

data "aws_vpc" "default" {
  default = true
}

data "aws_subnets" "default" {
  filter {
    name   = "vpc-id"
    values = [data.aws_vpc.default.id]
  }
}

resource "aws_security_group" "alb" {
  name        = "${var.app_name}-alb-sg"
  description = "Public ALB in front of the shipit app"
  vpc_id      = data.aws_vpc.default.id

  ingress {
    description = "Public HTTP — this is the demo API's public entry point"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    description = "All outbound"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = { Name = "${var.app_name}-alb-sg" }
}

resource "aws_security_group" "ecs_instance" {
  name        = "${var.app_name}-ecs-instance-sg"
  description = "Single ECS container instance running the shipit task"
  vpc_id      = data.aws_vpc.default.id

  ingress {
    description     = "App port, from the ALB only"
    from_port       = var.container_port
    to_port         = var.container_port
    protocol        = "tcp"
    security_groups = [aws_security_group.alb.id]
  }

  egress {
    description = "All outbound"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = { Name = "${var.app_name}-ecs-instance-sg" }
}
