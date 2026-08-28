# Default VPC, same pattern as the agentic-ai stack — simplest setup for a
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

resource "aws_security_group" "jenkins" {
  name        = "${var.app_name}-sg"
  description = "Jenkins controller (ECS Fargate)"
  vpc_id      = data.aws_vpc.default.id

  ingress {
    description = "Jenkins web UI"
    from_port   = 8080
    to_port     = 8080
    protocol    = "tcp"
    cidr_blocks = [var.admin_cidr]
  }

  ingress {
    description = "Jenkins agent JNLP"
    from_port   = 50000
    to_port     = 50000
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

  tags = { Name = "${var.app_name}-sg" }
}

resource "aws_security_group" "efs" {
  name        = "${var.app_name}-efs-sg"
  description = "Allow NFS from the Jenkins controller"
  vpc_id      = data.aws_vpc.default.id

  ingress {
    description     = "NFS from Jenkins controller"
    from_port       = 2049
    to_port         = 2049
    protocol        = "tcp"
    security_groups = [aws_security_group.jenkins.id]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = { Name = "${var.app_name}-efs-sg" }
}
