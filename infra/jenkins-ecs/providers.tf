terraform {
  required_version = ">= 1.5.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }

  # State lives in Terraform Cloud, same org as the agentic-ai stack, its
  # own workspace. `terraform apply` runs from GitHub Actions
  # (.github/workflows/infrastructure.yml), never from a local machine.
  cloud {
    organization = "agentic-ai-org"

    workspaces {
      name = "jfrog-demo-jenkins"
    }
  }
}

provider "aws" {
  region = var.aws_region
}
