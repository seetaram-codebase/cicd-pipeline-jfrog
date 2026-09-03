# One EC2 instance registered as an ECS "EC2" (not Fargate) container
# instance — same "keep it simple, one box" choice already made for
# Jenkins. Using a real ECS cluster/service/task-definition (rather than
# just docker-run on a bare instance) means the Jenkinsfile's existing
# `aws ecs update-service --cluster ... --service ...` deploy stage needs
# no changes at all.

data "aws_ssm_parameter" "ecs_ami" {
  name = "/aws/service/ecs/optimized-ami/amazon-linux-2/recommended"
}

locals {
  ecs_ami_id = jsondecode(data.aws_ssm_parameter.ecs_ami.value)["image_id"]
}

resource "aws_iam_role" "ecs_instance" {
  name = "${var.app_name}-ecs-instance-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action    = "sts:AssumeRole"
      Effect    = "Allow"
      Principal = { Service = "ec2.amazonaws.com" }
    }]
  })
}

# Lets the ECS agent on this box register the instance with the cluster
# and report task status back.
resource "aws_iam_role_policy_attachment" "ecs_instance" {
  role       = aws_iam_role.ecs_instance.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonEC2ContainerServiceforEC2Role"
}

# Browser-based shell via EC2 Console -> Connect -> Session Manager, same
# as the Jenkins instance — no key pair, no open port 22.
resource "aws_iam_role_policy_attachment" "ecs_instance_ssm" {
  role       = aws_iam_role.ecs_instance.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

resource "aws_iam_instance_profile" "ecs_instance" {
  name = "${var.app_name}-ecs-instance-profile"
  role = aws_iam_role.ecs_instance.name
}

resource "aws_instance" "ecs" {
  ami                         = local.ecs_ami_id
  instance_type               = var.instance_type
  subnet_id                   = data.aws_subnets.default.ids[0]
  vpc_security_group_ids      = [aws_security_group.ecs_instance.id]
  iam_instance_profile        = aws_iam_instance_profile.ecs_instance.name
  key_name                    = var.instance_key_name != "" ? var.instance_key_name : null
  associate_public_ip_address = true

  user_data = <<-EOT
    #!/bin/bash
    echo ECS_CLUSTER=${aws_ecs_cluster.app.name} >> /etc/ecs/ecs.config
  EOT

  tags = { Name = "${var.app_name}-ecs-instance" }
}
