resource "aws_ecs_cluster" "app" {
  name = var.app_name
}

resource "aws_cloudwatch_log_group" "app" {
  name              = "/ecs/${var.app_name}"
  retention_in_days = var.log_retention_days
}

# Container only, no value set here — same reasoning as jfrog-access-token
# never being committed to Jenkins credentials. Populate this manually
# after apply: {"username":"<jfrog-user>","password":"<jfrog-access-token>"}
resource "aws_secretsmanager_secret" "jfrog_pull_creds" {
  name        = "${var.app_name}-jfrog-pull-creds"
  description = "JFrog Artifactory pull credentials for the ECS task execution role's repositoryCredentials"
}

resource "aws_iam_role" "task_execution" {
  name = "${var.app_name}-task-execution-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action    = "sts:AssumeRole"
      Effect    = "Allow"
      Principal = { Service = "ecs-tasks.amazonaws.com" }
    }]
  })
}

resource "aws_iam_role_policy_attachment" "task_execution" {
  role       = aws_iam_role.task_execution.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}

# The managed policy above covers ECR + CloudWatch Logs, but pulling from
# a private *JFrog* registry via repositoryCredentials additionally needs
# direct read access to the specific secret holding those credentials.
resource "aws_iam_role_policy" "task_execution_secret" {
  name = "${var.app_name}-read-jfrog-secret"
  role = aws_iam_role.task_execution.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = "secretsmanager:GetSecretValue"
      Resource = aws_secretsmanager_secret.jfrog_pull_creds.arn
    }]
  })
}

# No extra AWS API access needed by the app itself.
resource "aws_iam_role" "task" {
  name = "${var.app_name}-task-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action    = "sts:AssumeRole"
      Effect    = "Allow"
      Principal = { Service = "ecs-tasks.amazonaws.com" }
    }]
  })
}

resource "aws_ecs_task_definition" "shipit" {
  family                   = "shipit"
  requires_compatibilities = ["EC2"]
  network_mode             = "bridge"
  cpu                      = var.task_cpu
  memory                   = var.task_memory
  execution_role_arn       = aws_iam_role.task_execution.arn
  task_role_arn            = aws_iam_role.task.arn

  # Nothing has been pushed to artifact-release yet at first apply, so
  # this is a placeholder — Jenkins registers a real revision (with the
  # freshly-built image) on every release-branch deploy. Terraform must
  # not fight that: ignore_changes stops it from reverting Jenkins'
  # revisions back to this placeholder on the next plan/apply.
  container_definitions = jsonencode([
    {
      name      = "shipit"
      image     = "${var.jfrog_registry}/artifact-release/shipit:bootstrap"
      essential = true
      repositoryCredentials = {
        credentialsParameter = aws_secretsmanager_secret.jfrog_pull_creds.arn
      }
      portMappings = [{
        containerPort = var.container_port
        hostPort      = var.container_port
        protocol      = "tcp"
      }]
      logConfiguration = {
        logDriver = "awslogs"
        options = {
          "awslogs-group"         = aws_cloudwatch_log_group.app.name
          "awslogs-region"        = var.aws_region
          "awslogs-stream-prefix" = "shipit"
        }
      }
    }
  ])

  lifecycle {
    ignore_changes = [container_definitions]
  }
}

resource "aws_ecs_service" "shipit_production" {
  name            = "shipit-production"
  cluster         = aws_ecs_cluster.app.id
  task_definition = aws_ecs_task_definition.shipit.arn
  desired_count   = 1
  launch_type     = "EC2"

  load_balancer {
    target_group_arn = aws_lb_target_group.app.arn
    container_name   = "shipit"
    container_port   = var.container_port
  }

  # ECS needs at least one registered container instance to place the
  # task on; the instance registers itself via user-data shortly after
  # boot, which Terraform doesn't wait on, but the service will simply
  # retry placement until it does.
  depends_on = [aws_instance.ecs, aws_lb_listener.http]

  lifecycle {
    ignore_changes = [task_definition]
  }
}
