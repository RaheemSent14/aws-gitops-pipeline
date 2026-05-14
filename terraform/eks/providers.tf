# providers.tf
# Intent: Configures active authentication hooks and initial default tags for AWS resource pools.
# Problem Solved: Injects local cloud credentials and standardizes infrastructure labeling for accounting.
# Pitfalls: Hardcoding credentials here leaks security vectors into public source repositories.
provider "aws" {
  region = var.aws_region

  default_tags {
    tags = {
      Environment = var.environment
      Project     = "aws-gitops-pipeline"
      ManagedBy   = "Terraform"
    }
  }
}

# Fetch temporary cryptographic authentication credentials from the core AWS cluster instance
data "aws_eks_cluster_auth" "cluster" {
  name = aws_eks_cluster.eks.name
}

provider "helm" {
  kubernetes {
    host                   = aws_eks_cluster.eks.endpoint
    cluster_ca_certificate = base64decode(aws_eks_cluster.eks.certificate_authority[0].data)
    token                  = data.aws_eks_cluster_auth.cluster.token
  }
}