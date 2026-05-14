# variables.tf
# Intent: Outlines structural inputs, type constraints, and fallback values for the execution plan.
# Problem Solved: Eliminates hardcoded variables, allowing configurations to change dynamically across environments.
variable "aws_region" {
  type        = string
  default     = "us-east-1"
  description = "Target geographical deployment plane for AWS resource allocations."
}

variable "environment" {
  type        = string
  default     = "dev"
  description = "Operational stage label applied to track resource groups."
}

variable "vpc_cidr" {
  type        = string
  default     = "10.0.0.0/16"
  description = "Primary network addressing block allocated for the virtual cloud footprint."
}