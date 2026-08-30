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

variable "admin_cidr" {
  description = "CIDR allowed to reach the Jenkins UI (8080). Defaults wide open for demo setup speed — narrow this to your IP before the session."
  type        = string
  default     = "0.0.0.0/0"
}

variable "jenkins_instance_type" {
  description = "Instance type for the combined Jenkins controller + build EC2 instance (needs a real Docker daemon; Fargate can't run docker build)"
  type        = string
  default     = "t3.medium"
}

variable "jenkins_key_name" {
  description = "EC2 key pair name for SSH access to the instance (optional, leave blank to skip — use SSM Session Manager instead)"
  type        = string
  default     = ""
}
