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
  description = "Jenkins controller + build execution (single EC2 instance)"
  vpc_id      = data.aws_vpc.default.id

  ingress {
    description = "Jenkins web UI / GitHub webhook"
    from_port   = 8080
    to_port     = 8080
    protocol    = "tcp"
    cidr_blocks = [var.admin_cidr]
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
