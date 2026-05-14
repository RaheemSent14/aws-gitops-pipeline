# versions.tf
# Intent: Establishes strict engine version constraints for the infrastructure configuration.
# Problem Solved: Prevents code execution errors caused by breaking syntax updates in newer provider versions.
# Pitfalls: If left unpinned, team members running different local binary versions will cause state file drift.
terraform {
  required_version = ">= 1.5.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    helm = {
      source  = "hashicorp/helm"
      version = "~> 2.12.0"
    }
  }
}