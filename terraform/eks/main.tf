# main.tf
# Intent: Provisions the underlying "Cloud Real Estate" (VPC) and "Brains" (EKS) of the system.
# Problem Solved: Replaces manual, error-prone console clicking with a repeatable, versioned audit trail.
# Business Value: Ensures that if our primary region goes down, we can rebuild the entire company infrastructure in minutes using this code.

data "aws_availability_zones" "available" {
  state = "available"
}

# 1. THE VIRTUAL PRIVATE CLOUD (VPC) SUBSYSTEM
# Architecture: Implements "Network Partitioning" with 2 Public and 2 Private subnets.
# Why it matters: We place our application in Private subnets to prevent direct internet 
# access, drastically reducing our "Attack Surface" (Blast Radius).
module "vpc" {
  source  = "terraform-aws-modules/vpc/aws"
  version = "~> 5.5.0"

  name = "gitops-core-vpc"
  cidr = var.vpc_cidr

  # High Availability (HA): Spread across 2 Availability Zones to survive a physical AWS data center failure.
  azs             = slice(data.aws_availability_zones.available.names, 0, 2)
  private_subnets = ["10.0.1.0/24", "10.0.2.0/24"]
  public_subnets  = ["10.0.101.0/24", "10.0.102.0/24"]

  # FINOPS VICTORY: Single NAT Gateway.
  # Production Context: Enterprises usually use one NAT per AZ ($90+/month). 
  # For this portfolio, we use a single NAT to provide outbound internet to our 
  # private pods while saving ~$45/month in idle infrastructure fees.
  enable_nat_gateway     = true
  single_nat_gateway     = true
  one_nat_gateway_per_az = false

  # DYNAMIC DISCOVERY TAGS: 
  # These are the "Signs" that tell the AWS Load Balancer Controller: 
  # "You are allowed to build an internet-facing entrance here."
  public_subnet_tags = {
    "kubernetes.io/role/elb" = "1"
  }
  private_subnet_tags = {
    "kubernetes.io/role/internal-elb" = "1"
  }
}

# 2. IAM: THE CLUSTER CONTROL ROLE
# Intent: Defines the "Powers" the EKS Brain has to manage AWS resources.
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
  role        = aws_iam_role.cluster.name
}

# 3. THE AMAZON EKS CONTROL PLANE (THE BRAIN)
resource "aws_eks_cluster" "eks" {
  name     = "gitops-cloud-cluster"
  role_arn = aws_iam_role.cluster.arn
  
  # FINOPS MASTERSTROKE: EKS 1.32.
  # Strategic Choice: By staying on a "Standard Support" version, we pay $0.10/hr. 
  # If we used version 1.28, AWS would charge an extra $0.50/hr for "Extended Support". 
  # This decision saves the business ~$360/month per cluster.
  version  = "1.32"

  vpc_config {
    endpoint_private_access = true # Internal pods talk to K8s API privately
    endpoint_public_access  = true # Allows us to manage the cluster from our local MacBook
    subnet_ids              = module.vpc.private_subnets
  }

  depends_on = [aws_iam_role_policy_attachment.cluster_policy]
}

# 4. IAM: WORKER NODE ROLE (THE MUSCLE)
# Intent: Permissions for the EC2 servers to join the cluster and download images from ECR.
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

# Standard attachments for Node health, Networking (CNI), and Registry (ECR) access.
resource "aws_iam_role_policy_attachment" "node_worker" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSWorkerNodePolicy"
  role        = aws_iam_role.node.name
}
resource "aws_iam_role_policy_attachment" "node_cni" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKS_CNI_Policy"
  role        = aws_iam_role.node.name
}
resource "aws_iam_role_policy_attachment" "node_registry" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly"
  role        = aws_iam_role.node.name
}

# 5. EKS MANAGED NODE GROUP (THE WORKFORCE)
resource "aws_eks_node_group" "nodes" {
  cluster_name    = aws_eks_cluster.eks.name
  node_group_name = "managed-linux-workers"
  node_role_arn   = aws_iam_role.node.arn
  subnet_ids      = module.vpc.private_subnets

  # INSTANCE SIZING: t3.small (2 vCPU, 2GiB RAM).
  # Technical Context: We chose t3.small because t3.micro does not have enough "Pods-per-Node" 
  # capacity to run the ArgoCD and Prometheus management agents.
  instance_types = ["t3.small"]

  scaling_config {
    # PERFORMANCE SOLUTION: desired_size = 2.
    # Why: A single node becomes "Saturated" by the overhead of Kubernetes system pods. 
    # Having 2 nodes provides the "Compute Runway" needed for our app to schedule successfully.
    desired_size = 2
    max_size     = 2
    min_size     = 1
  }

  depends_on = [
    aws_iam_role_policy_attachment.node_worker,
    aws_iam_role_policy_attachment.node_cni,
    aws_iam_role_policy_attachment.node_registry
  ]
}