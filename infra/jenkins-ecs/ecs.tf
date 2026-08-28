# Jenkins controller only. It schedules and displays pipelines, and serves
# the web UI + GitHub webhook endpoint — it does not run builds itself.
# See agent-ec2.tf for the EC2 instance that actually runs `docker build`.

resource "aws_ecs_cluster" "jenkins" {
  name = var.app_name

  setting {
    name  = "containerInsights"
    value = "enabled"
  }

  tags = { Name = "${var.app_name}-cluster" }
}

resource "aws_ecs_cluster_capacity_providers" "jenkins" {
  cluster_name       = aws_ecs_cluster.jenkins.name
  capacity_providers = ["FARGATE"]

  default_capacity_provider_strategy {
    base              = 1
    weight            = 100
    capacity_provider = "FARGATE"
  }
}

resource "aws_cloudwatch_log_group" "jenkins" {
  name              = "/ecs/${var.app_name}"
  retention_in_days = var.log_retention_days

  tags = { Name = "${var.app_name}-logs" }
}

resource "aws_ecs_task_definition" "jenkins" {
  family                   = var.app_name
  network_mode             = "awsvpc"
  requires_compatibilities = ["FARGATE"]
  cpu                      = var.jenkins_cpu
  memory                   = var.jenkins_memory
  execution_role_arn       = aws_iam_role.ecs_task_execution.arn
  task_role_arn            = aws_iam_role.jenkins_task.arn

  volume {
    name = "jenkins-home"

    efs_volume_configuration {
      file_system_id     = aws_efs_file_system.jenkins_home.id
      transit_encryption = "ENABLED"

      authorization_config {
        access_point_id = aws_efs_access_point.jenkins_home.id
        iam             = "ENABLED"
      }
    }
  }

  container_definitions = jsonencode([
    {
      name  = "jenkins"
      image = var.jenkins_image

      portMappings = [
        { containerPort = 8080, hostPort = 8080, protocol = "tcp" },
        { containerPort = 50000, hostPort = 50000, protocol = "tcp" }
      ]

      mountPoints = [
        {
          sourceVolume  = "jenkins-home"
          containerPath = "/var/jenkins_home"
        }
      ]

      logConfiguration = {
        logDriver = "awslogs"
        options = {
          "awslogs-group"         = aws_cloudwatch_log_group.jenkins.name
          "awslogs-region"        = var.aws_region
          "awslogs-stream-prefix" = "jenkins"
        }
      }

      healthCheck = {
        command     = ["CMD-SHELL", "curl -sf http://localhost:8080/login || exit 1"]
        interval    = 30
        timeout     = 10
        retries     = 3
        startPeriod = 120
      }
    }
  ])

  tags = { Name = "${var.app_name}-task" }
}

resource "aws_ecs_service" "jenkins" {
  name            = "jenkins"
  cluster         = aws_ecs_cluster.jenkins.id
  task_definition = aws_ecs_task_definition.jenkins.arn
  desired_count   = 1
  launch_type     = "FARGATE"

  network_configuration {
    subnets          = data.aws_subnets.default.ids
    security_groups  = [aws_security_group.jenkins.id]
    assign_public_ip = true
  }

  load_balancer {
    target_group_arn = aws_lb_target_group.jenkins.arn
    container_name   = "jenkins"
    container_port   = 8080
  }

  depends_on = [aws_efs_mount_target.jenkins_home, aws_lb_listener.jenkins]

  lifecycle {
    ignore_changes = [task_definition]
  }

  tags = { Name = "${var.app_name}-service" }
}
