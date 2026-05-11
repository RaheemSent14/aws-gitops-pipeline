variable "aws_region" {
  type    = string
  default = "us-east-1"
}

variable "repository_name" {
  type    = string
  default = "gitops-demo"
}

variable "environment" {
  type    = string
  default = "dev"
}