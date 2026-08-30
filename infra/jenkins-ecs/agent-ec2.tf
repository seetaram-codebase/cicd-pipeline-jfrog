# Single EC2 instance running both the Jenkins controller and the actual
# build execution. Docker builds need a real (non-Fargate) Docker daemon;
# now that Jenkins itself lives here too, there's no controller/agent
# split to wire up — pipeline stages run on this box's built-in node.

data "aws_ami" "ubuntu" {
  most_recent = true
  owners      = ["099720109477"] # Canonical

  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd/ubuntu-jammy-22.04-amd64-server-*"]
  }
}

resource "aws_iam_role" "jenkins" {
  name = "${var.app_name}-role"

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
resource "aws_iam_role_policy" "jenkins_deploy" {
  name = "${var.app_name}-deploy"
  role = aws_iam_role.jenkins.id

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

# Lets you reach the instance through EC2 Console → Connect → Session
# Manager (browser-based shell) instead of SSH — no key pair, no open
# port 22. Ubuntu's official Canonical AMI ships the SSM agent
# preinstalled; this just grants it permission to register.
resource "aws_iam_role_policy_attachment" "jenkins_ssm" {
  role       = aws_iam_role.jenkins.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

resource "aws_iam_instance_profile" "jenkins" {
  name = "${var.app_name}-profile"
  role = aws_iam_role.jenkins.name
}

resource "aws_instance" "jenkins" {
  ami                         = data.aws_ami.ubuntu.id
  instance_type               = var.jenkins_instance_type
  subnet_id                   = data.aws_subnets.default.ids[0]
  vpc_security_group_ids      = [aws_security_group.jenkins.id]
  iam_instance_profile        = aws_iam_instance_profile.jenkins.name
  key_name                    = var.jenkins_key_name != "" ? var.jenkins_key_name : null
  associate_public_ip_address = true

  # Default 8GB is too small once this box holds JENKINS_HOME plus
  # pulled/built Docker images.
  root_block_device {
    volume_type = "gp3"
    volume_size = 30
  }

  user_data = file("${path.module}/agent-userdata.sh")

  tags = { Name = var.app_name }
}

# Fargate re-IP'd on every restart, which is why an ALB got added. A
# single EC2 instance already keeps its IP unless stopped/started, but an
# EIP makes that guarantee absolute — much simpler than an ALB for the
# same "stable address" property.
resource "aws_eip" "jenkins" {
  instance = aws_instance.jenkins.id
  domain   = "vpc"

  tags = { Name = "${var.app_name}-eip" }
}
