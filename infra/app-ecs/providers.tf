terraform {
  required_version = ">= 1.5.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }

  # State lives in Terraform Cloud, same org as the rest of this repo's
  # infra, its own workspace. `terraform apply` runs from GitHub Actions
  # (.github/workflows/app-infrastructure.yml), never from a local machine.
  cloud {
    organization = "agentic-ai-org"

    workspaces {
      name = "jfrog-demo-app"
    }
  }
}

provider "aws" {
  region = var.aws_region
}
