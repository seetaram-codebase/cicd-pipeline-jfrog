# Jenkins build agent (EC2, not Fargate). Fargate disallows privileged
# containers, so `docker build` cannot run on the controller — this instance
# has a real Docker daemon and is where the Jenkinsfile's `agent { label
# 'build' }` stages actually execute. Attach it as a node manually from the
# Jenkins UI after boot (Manage Jenkins > Nodes > New Node > Launch agent by
# connecting it to the controller), label it "build".

data "aws_ami" "ubuntu" {
  most_recent = true
  owners      = ["099720109477"] # Canonical

  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd/ubuntu-jammy-22.04-amd64-server-*"]
  }
}

resource "aws_security_group" "build_agent" {
  name        = "${var.app_name}-agent-sg"
  description = "Jenkins build agent"
  vpc_id      = data.aws_vpc.default.id

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = { Name = "${var.app_name}-agent-sg" }
}

resource "aws_iam_role" "build_agent" {
  name = "${var.app_name}-agent-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action    = "sts:AssumeRole"
      Effect    = "Allow"
      Principal = { Service = "ec2.amazonaws.com" }
    }]
  })
}

# Lets the Jenkinsfile run `aws ecs update-service` for deploys without
# static AWS keys stored in Jenkins credentials.
resource "aws_iam_role_policy" "build_agent_deploy" {
  name = "${var.app_name}-agent-deploy"
  role = aws_iam_role.build_agent.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "ecs:UpdateService",
          "ecs:DescribeServices",
          "ecs:DescribeTaskDefinition",
          "ecs:RegisterTaskDefinition"
        ]
        Resource = "*"
      },
      {
        Effect   = "Allow"
        Action   = "iam:PassRole"
        Resource = "*"
        Condition = {
          StringEquals = { "iam:PassedToService" = "ecs-tasks.amazonaws.com" }
        }
      }
    ]
  })
}

resource "aws_iam_instance_profile" "build_agent" {
  name = "${var.app_name}-agent-profile"
  role = aws_iam_role.build_agent.name
}

resource "aws_instance" "build_agent" {
  ami                         = data.aws_ami.ubuntu.id
  instance_type               = var.agent_instance_type
  subnet_id                   = data.aws_subnets.default.ids[0]
  vpc_security_group_ids      = [aws_security_group.build_agent.id]
  iam_instance_profile        = aws_iam_instance_profile.build_agent.name
  key_name                    = var.agent_key_name != "" ? var.agent_key_name : null
  associate_public_ip_address = true

  user_data = file("${path.module}/agent-userdata.sh")

  tags = { Name = "${var.app_name}-build-agent" }
}
