# AWS EKS Core Clusters Provisioner

## Architecture Profile
This automation framework spins up a production-grade AWS cloud footprint hosting a secure Amazon EKS engine container environment:
* **Networking Mesh:** 1x isolated Virtual Private Cloud (VPC) with public/private subnet pairs split across multiple availability zones, backed by a single NAT Gateway layer.
* **Management Plane:** 1x managed Amazon EKS Cluster Control Plane (running Kubernetes version 1.29).
* **Execution Layer:** 1x Managed Node Group running `t3.small` server layers locked inside private subnets for security isolation.

## Cost Metrics Forecast
* Amazon EKS Control Plane: Fix rate of $0.10/hour.
* Compute Instances (1x active `t3.small` base): ~$0.0208/hour.
* Networking Mappings (NAT Gateway uptime base): ~$0.045/hour.
* **Aggregated Operating Estimate:** ~$0.17 per hour.

## Deployment Playbook
```bash
terraform init
terraform plan -out=eks-deployment.tfplan
terraform apply "eks-deployment.tfplan"