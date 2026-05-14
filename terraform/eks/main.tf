# main.tf
# Intent: Defines the explicit architectural state for the VPC, IAM mappings, and EKS resources.
# Problem Solved: Builds a functional network mesh and computes infrastructure automatically.
# Business Value: Establishes a secure, repeatable infrastructure foundation that segregates public traffic from backend application compute nodes.

data "aws_availability_zones" "available" {
  state = "available"
}

# 1. Virtual Private Cloud (VPC) Subsystem
# Architecture: Deploys 2 Public subnets for edge routing and 2 Private subnets for compute containment.
# Why it matters: Segregates public-facing ingress resources from sensitive backend data and compute elements.
# Pitfalls: Missing the explicit ELB tags will cause downstream Kubernetes ingress controllers to fail when provisioning AWS load balancers automatically.
module "vpc" {
  source  = "terraform-aws-modules/vpc/aws"
  version = "~> 5.5.0"

  name = "gitops-core-vpc"
  cidr = var.vpc_cidr

  # Distribute network layers evenly across the first two active Availability Zones
  azs             = slice(data.aws_availability_zones.available.names, 0, 2)
  private_subnets = ["10.0.1.0/24", "10.0.2.0/24"]
  public_subnets  = ["10.0.101.0/24", "10.0.102.0/24"]

  # FinOps Optimization: Consolidates outbound private routing traffic into a single NAT gateway instance.
  # This avoids the standard enterprise cost of a NAT Gateway per Availability Zone during development and portfolio review.
  enable_nat_gateway     = true
  single_nat_gateway     = true
  one_nat_gateway_per_az = false

  # Required internal annotations enabling automated AWS Application Load Balancer discovery engines.
  # These tags allow the AWS Load Balancer Controller inside the cluster to identify target subnets for routing traffic.
  public_subnet_tags = {
    "kubernetes.io/role/elb" = "1"
  }
  private_subnet_tags = {
    "kubernetes.io/role/internal-elb" = "1"
  }
}

# 2. IAM Configuration: Control Plane Management Role
# Intent: Establishes an identity blueprint allowing the EKS service to manage underlying infrastructure components.
# Why it matters: Enforces strict separation of duties; the control plane role does not share credentials with worker nodes.
resource "aws_iam_role" "cluster" {
  name = "eks-cluster-control-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action    = "sts:AssumeRole"
      Effect    = "Allow"
      Principal = { Service = "eks.amazonaws.com" }
    }]
  })
}

resource "aws_iam_role_policy_attachment" "cluster_policy" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSClusterPolicy"
  role       = aws_iam_role.cluster.name
}

# 3. Amazon EKS Control Plane
# Intent: Provisions the managed Kubernetes master nodes orchestrating api requests and state tracking.
# Why it matters: Acts as the brain of the container platform, isolating critical internal components from direct network manipulation.
resource "aws_eks_cluster" "eks" {
  name     = "gitops-cloud-cluster"
  role_arn = aws_iam_role.cluster.arn
  
  # FinOps Compliance: Set to 1.32 to leverage AWS Standard Support baselines.
  # This choice keeps our control plane billing flat at $0.10/hour, completely evading 
  # the $0.60/hour Extended Support price penalties enforced on legacy infrastructure tracks.
  version  = "1.32"

  vpc_config {
    endpoint_private_access = true
    endpoint_public_access  = true
    subnet_ids              = module.vpc.private_subnets
  }

  # Safety Guard: Ensures IAM policies exist before the cluster initializes to prevent provisioning runtime race conditions.
  depends_on = [aws_iam_role_policy_attachment.cluster_policy]
}

# 4. IAM Configuration: Data Plane Worker Node Role
# Intent: Provides worker nodes with identity permissions to register with the master control plane and stream logs.
# Why it matters: Implements cloud-native authentication, removing the need to manage static private keys or configuration passwords inside pods.
resource "aws_iam_role" "node" {
  name = "eks-worker-node-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action    = "sts:AssumeRole"
      Effect    = "Allow"
      Principal = { Service = "ec2.amazonaws.com" }
    }]
  })
}

resource "aws_iam_role_policy_attachment" "node_worker" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSWorkerNodePolicy"
  role       = aws_iam_role.node.name
}

resource "aws_iam_role_policy_attachment" "node_cni" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKS_CNI_Policy"
  role       = aws_iam_role.node.name
}

resource "aws_iam_role_policy_attachment" "node_registry" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly"
  role       = aws_iam_role.node.name
}

# 5. Amazon EKS Managed Node Group
# Intent: Provisions the auto-scaling pool of EC2 instances serving as compute workers for our live workloads.
# Why it matters: Hosts our actual application pods and core cluster extensions like ArgoCD.
# Pitfalls: Setting desired_size to 1 causes resource starvation when running complex management stacks alongside applications.
resource "aws_eks_node_group" "nodes" {
  cluster_name    = aws_eks_cluster.eks.name
  node_group_name = "managed-linux-workers"
  node_role_arn   = aws_iam_role.node.arn
  subnet_ids      = module.vpc.private_subnets

  # Compute Selection: Configured with t3.small instances to handle running ArgoCD and our Flask workload efficiently.
  instance_types = ["t3.small"]

  scaling_config {
    # Horizontal Capacity Scaling Solution: Upgraded from 1 to 2 active compute machines.
    # This change expands cluster compute runway to resolve scheduling bottleneck limits, 
    # giving the EKS scheduler enough room to run our Flask application pods alongside the ArgoCD suite.
    desired_size = 2
    max_size     = 2
    min_size     = 1
  }

  # Safety Guard: Prevents nodes from booting before their respective networking and ECR tracking policies are fully active.
  depends_on = [
    aws_iam_role_policy_attachment.node_worker,
    aws_iam_role_policy_attachment.node_cni,
    aws_iam_role_policy_attachment.node_registry
  ]
}