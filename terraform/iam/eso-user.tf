# eso-user.tf
# Intent: Provisions a dedicated programmatic identity for the External Secrets Operator.
# In a production setting, we avoid using "Root" or "Admin" credentials. Instead, we 
# create a Service Account with a tightly scoped policy that only allows 
# read-only access to a specific path in AWS Secrets Manager.

resource "aws_iam_user" "eso_user" {
  name = "external-secrets-operator-service-account"
  
  tags = {
    Project = "GitOps-Portfolio"
    Role    = "Security-Bridge"
  }
}

resource "aws_iam_access_key" "eso_key" {
  user = aws_iam_user.eso_user.name
}

# LEAST PRIVILEGE POLICY:
# In a production setting, this is our "Security Firewall". 
# It limits the Operator to only two specific actions (Get and Describe) 
# and restricts its "vision" to only secrets prefixed with 'gitops-demo/'.
resource "aws_iam_policy" "eso_policy" {
  name        = "ESO-Secrets-Read-Only"
  description = "Allows ESO to read specific application secrets only"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Action   = [
          "secretsmanager:GetSecretValue",
          "secretsmanager:DescribeSecret"
        ]
        # RESOURCE SCOPING: By using a wildcard at the end of the path, we allow 
        # the operator to manage all secrets within the 'gitops-demo' folder 
        # without needing to update this Terraform code every time we add a new secret.
        # This is a critical SecOps boundary that prevents the operator from 
        # seeing unrelated organizational secrets.
        Resource = "arn:aws:secretsmanager:us-east-1:*:secret:gitops-demo/*"
      }
    ]
  })
}

resource "aws_iam_user_policy_attachment" "eso_attach" {
  user       = aws_iam_user.eso_user.name
  policy_arn = aws_iam_policy.eso_policy.arn
}

# OUTPUTS:
# In a production setting, we mark the secret_key as 'sensitive' so Terraform 
# hides it from standard console logs and CI/CD job outputs, preventing 
# accidental credential leakage.
output "eso_access_key" {
  value = aws_iam_access_key.eso_key.id
}

output "eso_secret_key" {
  value     = aws_iam_access_key.eso_key.secret
  sensitive = true
}