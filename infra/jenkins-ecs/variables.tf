variable "aws_region" {
  description = "AWS region"
  type        = string
  default     = "us-east-1"
}

variable "app_name" {
  description = "Name prefix for resources"
  type        = string
  default     = "jfrog-demo-jenkins"
}

variable "jenkins_cpu" {
  type    = number
  default = 1024
}

variable "jenkins_memory" {
  type    = number
  default = 2048
}

variable "jenkins_image" {
  description = "Jenkins controller image"
  type        = string
  default     = "jenkins/jenkins:lts-jdk17"
}

variable "log_retention_days" {
  type    = number
  default = 7
}

variable "admin_cidr" {
  description = "CIDR allowed to reach the Jenkins UI (8080). Defaults wide open for demo setup speed — narrow this to your IP before the session."
  type        = string
  default     = "0.0.0.0/0"
}

variable "agent_instance_type" {
  description = "Instance type for the EC2 Jenkins build agent (needs a real Docker daemon; Fargate can't run docker build)"
  type        = string
  default     = "t3.small"
}

variable "agent_key_name" {
  description = "EC2 key pair name for SSH access to the build agent (optional, leave blank to skip)"
  type        = string
  default     = ""
}
