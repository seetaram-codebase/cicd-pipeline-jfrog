variable "aws_region" {
  description = "AWS region"
  type        = string
  default     = "us-east-1"
}

# Must stay exactly this — it's the ECS cluster name the Jenkinsfile's
# ECS_CLUSTER env var already targets (fastapi-jfrog-demo/Jenkinsfile).
variable "app_name" {
  description = "Name for the ECS cluster (also used as a prefix for other resources)"
  type        = string
  default     = "jfrog-demo-app"
}

variable "instance_type" {
  description = "Instance type for the single ECS container-instance (small — one small FastAPI task)"
  type        = string
  default     = "t3.small"
}

variable "instance_key_name" {
  description = "EC2 key pair name for SSH access to the instance (optional, leave blank — use SSM Session Manager instead)"
  type        = string
  default     = ""
}

variable "container_port" {
  description = "Port the app container listens on"
  type        = number
  default     = 8000
}

variable "task_cpu" {
  description = "Task-level CPU units (this is a small demo FastAPI app)"
  type        = number
  default     = 256
}

variable "task_memory" {
  description = "Task-level memory in MB, hard limit"
  type        = number
  default     = 400
}

variable "log_retention_days" {
  description = "CloudWatch log retention for the app container's logs"
  type        = number
  default     = 14
}

variable "jfrog_registry" {
  description = "JFrog Docker registry host, for the placeholder task definition image and Secrets Manager repositoryCredentials"
  type        = string
  default     = "trialkj7tft.jfrog.io"
}
