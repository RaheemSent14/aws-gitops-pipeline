# outputs.tf
# Intent: Surfaces critical network and cluster access parameters required for downstream tooling integrations.
# Problem Solved: Exposes generated cluster configuration strings without requiring manual state file lookups.
output "cluster_name" {
  description = "The target structural identifier of the active EKS instance."
  value       = aws_eks_cluster.eks.name
}

output "cluster_endpoint" {
  description = "The secure network gateway URL used to execute commands against the cluster API."
  value       = aws_eks_cluster.eks.endpoint
}

output "vpc_private_subnets" {
  description = "A structural array listing the generated private subnet IDs."
  value       = module.vpc.private_subnets
}