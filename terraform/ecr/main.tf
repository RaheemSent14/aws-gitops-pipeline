# The ECR Repository
resource "aws_ecr_repository" "app_repo" {
  name                 = var.repository_name
  
  # SecOps: Prevents an image tag from being overwritten. 
  # This guarantees that if you deploy commit SHA 'abc1234', it is exactly what you built.
  image_tag_mutability = "IMMUTABLE"

  image_scanning_configuration {
    # Belt-and-suspenders: Scans the image using AWS native tools upon push, 
    # acting as a secondary check to our Trivy CI pipeline.
    scan_on_push = true
  }
}

# FinOps: Lifecycle policy to delete old images and save storage costs.
resource "aws_ecr_lifecycle_policy" "cleanup_policy" {
  repository = aws_ecr_repository.app_repo.name

  policy = <<EOF
{
    "rules": [
        {
            "rulePriority": 1,
            "description": "Keep last 10 images",
            "selection": {
                "tagStatus": "any",
                "countType": "imageCountMoreThan",
                "countNumber": 10
            },
            "action": {
                "type": "expire"
            }
        }
    ]
}
EOF
}

# SecOps: The IAM User for GitHub Actions
resource "aws_iam_user" "ci_user" {
  name = "github-actions-ecr"
}

# Access Keys for the CI user
resource "aws_iam_access_key" "ci_user_keys" {
  user = aws_iam_user.ci_user.name
}

# Least Privilege Policy
resource "aws_iam_user_policy" "ci_user_policy" {
  name = "ecr-push-pull-only"
  user = aws_iam_user.ci_user.name

  # Note: GetAuthorizationToken must apply to all resources ("*").
  # The actual read/write actions are locked strictly to our single repository ARN.
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action   = ["ecr:GetAuthorizationToken"]
        Effect   = "Allow"
        Resource = "*"
      },
      {
        Action = [
          "ecr:BatchCheckLayerAvailability",
          "ecr:PutImage",
          "ecr:InitiateLayerUpload",
          "ecr:UploadLayerPart",
          "ecr:CompleteLayerUpload",
          "ecr:BatchGetImage"
        ]
        Effect   = "Allow"
        Resource = aws_ecr_repository.app_repo.arn
      }
    ]
  })
}