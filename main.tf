
# ─────────── RoleBinding for barakat-dev-view (kept for compatibility) ───────────
# NOTE: This is now optional/redundant because we use modern EKS Access Entries below.
# You can safely delete this block later if you want a cleaner file.
resource "kubernetes_role_binding" "barakat_dev_view" {
  metadata {
    name      = "barakat-dev-view-binding"
    namespace = kubernetes_namespace.retail_app.metadata[0].name
  }

  role_ref {
    api_group = "rbac.authorization.k8s.io"
    kind      = "ClusterRole"
    name      = "view"       # gives read-only access in this namespace
  }

  subject {
    kind      = "User"
    name      = "barakat-dev-view"  # must match aws-auth username
    api_group = "rbac.authorization.k8s.io"
  }
}

provider "aws" {
  region = "us-east-1"
  default_tags {
    tags = {
      Project = "barakat-2025-capstone"
    }
  }
}

data "aws_caller_identity" "current" {}

module "vpc" {
  source  = "terraform-aws-modules/vpc/aws"
  version = "~> 5.0"

  name = "barakat-2025-capstone-vpc"
  cidr = "10.0.0.0/16"

  azs             = ["us-east-1a", "us-east-1b"]
  private_subnets = ["10.0.1.0/24", "10.0.2.0/24"]
  public_subnets  = ["10.0.101.0/24", "10.0.102.0/24"]

  enable_nat_gateway     = true
  single_nat_gateway     = true
  one_nat_gateway_per_az = false
}

module "eks" {
  source  = "terraform-aws-modules/eks/aws"
  version = "~> 20.0"

  cluster_name    = "barakat-2025-capstone-cluster"
  cluster_version = "1.34"

  vpc_id     = module.vpc.vpc_id
  subnet_ids = module.vpc.private_subnets

  cluster_endpoint_public_access  = true
  cluster_endpoint_private_access = true

  cluster_enabled_log_types = ["api", "audit", "authenticator", "controllerManager", "scheduler"]

  eks_managed_node_groups = {
    default = {
      min_size       = 3
      max_size       = 4
      desired_size   = 4
      instance_types = ["t3.small"]
      capacity_type  = "ON_DEMAND"
    }
  }

  cluster_addons = {
    amazon-cloudwatch-observability = {
      most_recent = true
      configuration_values = jsonencode({
        agent = {
          resources = {
            requests = {
              cpu    = "100m"
              memory = "128Mi"
            }
            limits = {
              cpu    = "200m"
              memory = "256Mi"
            }
          }
        }
      })
    }
  }

}

# ─────────── EKS Access Entry for barakat-dev-view (MODERN & RECOMMENDED) ───────────
resource "aws_eks_access_entry" "barakat_dev_view" {
  cluster_name  = module.eks.cluster_name
  principal_arn = aws_iam_user.dev_view.arn
  type          = "STANDARD"
}

resource "aws_eks_access_policy_association" "barakat_dev_view" {
  cluster_name  = module.eks.cluster_name
  principal_arn = aws_iam_user.dev_view.arn
  policy_arn    = "arn:aws:eks::aws:cluster-access-policy/AmazonEKSViewPolicy"

  access_scope {
    type = "cluster"   # cluster-wide read-only (exactly what the assignment wants)
  }

  depends_on = [aws_eks_access_entry.barakat_dev_view]
}

data "aws_eks_cluster_auth" "cluster" {
  name = module.eks.cluster_name
}

provider "kubernetes" {
  host                   = module.eks.cluster_endpoint
  cluster_ca_certificate = base64decode(module.eks.cluster_certificate_authority_data)
  token                  = data.aws_eks_cluster_auth.cluster.token
}

# IAM User for developer access
resource "aws_iam_user" "dev_view" {
  name = "barakat-dev-view"
}

resource "aws_iam_user_policy_attachment" "readonly" {
  user       = aws_iam_user.dev_view.name
  policy_arn = "arn:aws:iam::aws:policy/ReadOnlyAccess"
}

resource "aws_iam_access_key" "dev_view_key" {
  user = aws_iam_user.dev_view.name
}

resource "aws_iam_user_login_profile" "dev_view_console" {
  user                        = aws_iam_user.dev_view.name
  password_reset_required     = false
}

resource "aws_iam_user_policy" "s3_put" {
  name = "barakat-s3-put-assets"
  user = aws_iam_user.dev_view.name
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action   = "s3:PutObject"
      Effect   = "Allow"
      Resource = "${aws_s3_bucket.assets.arn}/*"
    }]
  })
}

# aws-auth ConfigMap mapping for dev user

# Namespace for retail-app (added if missing)
resource "kubernetes_namespace" "retail_app" {
  metadata {
    name = "retail-app"
  }
}

# S3 Bucket for assets
resource "aws_s3_bucket" "assets" {
  bucket = "barakat-assets-1484"
}

# Lambda IAM Role
resource "aws_iam_role" "lambda_role" {
  name = "barakat-lambda-role"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action = "sts:AssumeRole"
      Effect = "Allow"
      Principal = { Service = "lambda.amazonaws.com" }
    }]
  })
}

resource "aws_iam_role_policy_attachment" "lambda_logs" {
  role       = aws_iam_role.lambda_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

# Lambda Function
data "archive_file" "lambda_zip" {
  type        = "zip"
  source_file = "lambda/lambda_function.py"
  output_path = "lambda/lambda.zip"
}

resource "aws_lambda_function" "asset_processor" {
  filename      = data.archive_file.lambda_zip.output_path
  function_name = "barakat-asset-processor"
  role          = aws_iam_role.lambda_role.arn
  handler       = "lambda_function.lambda_handler"
  runtime       = "python3.9"
}

resource "aws_s3_bucket_notification" "bucket_notification" {
  bucket = aws_s3_bucket.assets.id
  lambda_function {
    lambda_function_arn = aws_lambda_function.asset_processor.arn
    events              = ["s3:ObjectCreated:*"]
  }
}

resource "aws_lambda_permission" "allow_s3" {
  statement_id  = "AllowExecutionFromS3"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.asset_processor.function_name
  principal     = "s3.amazonaws.com"
  source_arn    = aws_s3_bucket.assets.arn
}

# ────────────────────────────────────────────────────────────────────────────────
# Bonus: Managed Persistence (RDS) – fully commented out for now
# ────────────────────────────────────────────────────────────────────────────────

# resource "aws_security_group" "rds_sg" { ... }  (all RDS resources commented)

# ────────────────────────────────────────────────────────────────────────────────
# Bonus: Advanced Networking (ALB) – only IRSA role active
# ────────────────────────────────────────────────────────────────────────────────

module "lb_controller_irsa" {
  source  = "terraform-aws-modules/iam/aws//modules/iam-role-for-service-accounts-eks"
  version = "~> 5.35"

  role_name = "barakat-alb-controller"
  attach_load_balancer_controller_policy = true
  oidc_providers = {
    main = {
      provider_arn               = module.eks.oidc_provider_arn
      namespace_service_accounts = ["kube-system:aws-load-balancer-controller"]
    }
  }
}
