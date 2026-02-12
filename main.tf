provider "aws" {
  region = "us-east-1"
   default_tags {
    tags = {
      Project         = "barakat-2025-capstone"
      AdmissionNumber = "1484"
    }
  }
}

data "aws_caller_identity" "current" {}

module "vpc" {
  source  = "terraform-aws-modules/vpc/aws"
  version = "~> 5.0"

  name = "project-bedrock-vpc"
  cidr = "10.0.0.0/16"

  azs             = ["us-east-1a", "us-east-1b"]
  private_subnets = ["10.0.1.0/24", "10.0.2.0/24"]
  public_subnets  = ["10.0.101.0/24", "10.0.102.0/24"]

  enable_nat_gateway = true
  single_nat_gateway = true

  tags = {
    Project = "barakat-2025-capstone"
  }
}

module "eks" {
  source  = "terraform-aws-modules/eks/aws"
  version = "~> 20.0"

  cluster_name    = "project-bedrock-cluster"
  cluster_version = "1.30"

  vpc_id     = module.vpc.vpc_id
  subnet_ids = module.vpc.private_subnets

  cluster_enabled_log_types = ["api", "audit", "authenticator", "controllerManager", "scheduler"]

  eks_managed_node_groups = {
    default = {
      min_size     = 1
      max_size     = 3
      desired_size = 2
      instance_types = ["t3.medium"]
    }
  }

  cluster_addons = {
    amazon-cloudwatch-observability = {
      most_recent = true
    }
  }

  tags = {
    Project = "barakat-2025-capstone"
  }
}

data "aws_eks_cluster_auth" "cluster" {
  name = module.eks.cluster_name
}

provider "kubernetes" {
  host                   = module.eks.cluster_endpoint
  cluster_ca_certificate = base64decode(module.eks.cluster_certificate_authority_data)
  token                  = data.aws_eks_cluster_auth.cluster.token
}

provider "helm" {
  kubernetes {
    host                   = module.eks.cluster_endpoint
    cluster_ca_certificate = base64decode(module.eks.cluster_certificate_authority_data)
    token                  = data.aws_eks_cluster_auth.cluster.token
  }
}

# IAM User: bedrock-dev-view
resource "aws_iam_user" "dev_view" {
  name = "bedrock-dev-view"
  tags = { Project = "barakat-2025-capstone" }
}

resource "aws_iam_user_policy_attachment" "readonly" {
  user       = aws_iam_user.dev_view.name
  policy_arn = "arn:aws:iam::aws:policy/ReadOnlyAccess"
}

resource "aws_iam_access_key" "dev_view_key" {
  user = aws_iam_user.dev_view.name
}

resource "aws_iam_user_login_profile" "dev_view_console" {
  user                    = aws_iam_user.dev_view.name
  password_reset_required = true
}

# S3 Put for user
resource "aws_iam_user_policy" "s3_put" {
  name = "S3PutForAssets"
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

# K8s RBAC for user
resource "kubernetes_config_map_v1_data" "aws_auth" {
  metadata {
    name      = "aws-auth"
    namespace = "kube-system"
  }
  data = {
    mapUsers = yamlencode([
      {
        userarn  = "arn:aws:iam::${data.aws_caller_identity.current.account_id}:user/bedrock-dev-view"
        username = "bedrock-dev-view"
        groups   = ["system:authenticated"]
      }
    ])
  }
}

resource "kubernetes_role_binding" "dev_view_binding" {
  metadata {
    name      = "dev-view-binding"
    namespace = "retail-app"
  }
  role_ref {
    api_group = "rbac.authorization.k8s.io"
    kind      = "ClusterRole"
    name      = "view"
  }
  subject {
    kind = "User"
    name = "bedrock-dev-view"
  }
}

# S3 Bucket
resource "aws_s3_bucket" "assets" {
  bucket = "bedrock-assets-${var.student_id}"
  tags   = { Project = "barakat-2025-capstone" }
}

# Lambda Role
resource "aws_iam_role" "lambda_role" {
  name = "bedrock-lambda-role"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action = "sts:AssumeRole"
      Effect = "Allow"
      Principal = { Service = "lambda.amazonaws.com" }
    }]
  })
  tags = { Project = "barakat-2025-capstone" }
}

resource "aws_iam_role_policy_attachment" "lambda_basic" {
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
  function_name = "bedrock-asset-processor"
  role          = aws_iam_role.lambda_role.arn
  handler       = "lambda_function.lambda_handler"
  runtime       = "python3.9"
  tags          = { Project = "barakat-2025-capstone" }
}

# S3 Notification
resource "aws_s3_bucket_notification" "bucket_notification" {
  bucket = aws_s3_bucket.assets.id
  lambda_function {
    lambda_function_arn = aws_lambda_function.asset_processor.arn
    events              = ["s3:ObjectCreated:*"]
  }
}

resource "aws_lambda_permission" "s3_invoke" {
  statement_id  = "AllowS3Invoke"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.asset_processor.function_name
  principal     = "s3.amazonaws.com"
  source_arn    = aws_s3_bucket.assets.arn
}

# Bonus RDS
resource "aws_security_group" "rds_sg" {
  name        = "rds-sg"
  description = "Allow EKS to RDS"
  vpc_id      = module.vpc.vpc_id
  ingress {
    from_port       = 3306
    to_port         = 3306
    protocol        = "tcp"
    security_groups = module.eks.node_security_group_id
  }
  ingress {
    from_port       = 5432
    to_port         = 5432
    protocol        = "tcp"
    security_groups = module.eks.node_security_group_id
  }
  tags = { Project = "barakat-2025-capstone" }
}

resource "aws_db_subnet_group" "main" {
  name       = "main"
  subnet_ids = module.vpc.private_subnets
  tags       = { Project = "barakat-2025-capstone" }
}

resource "aws_db_instance" "mysql_catalog" {
  allocated_storage    = 20
  storage_type         = "gp2"
  engine               = "mysql"
  engine_version       = "8.0"
  instance_class       = "db.t3.micro"
  db_name              = "catalog"
  username             = "admin"
  password             = "securepass"
  parameter_group_name = "default.mysql8.0"
  db_subnet_group_name = aws_db_subnet_group.main.name
  vpc_security_group_ids = [aws_security_group.rds_sg.id]
  skip_final_snapshot  = true
  tags                 = { Project = "barakat-2025-capstone" }
}

resource "aws_db_instance" "postgres_orders" {
  allocated_storage    = 20
  storage_type         = "gp2"
  engine               = "postgres"
  engine_version       = "13"
  instance_class       = "db.t3.micro"
  db_name              = "orders"
  username             = "admin"
  password             = "securepass"
  parameter_group_name = "default.postgres13"
  db_subnet_group_name = aws_db_subnet_group.main.name
  vpc_security_group_ids = [aws_security_group.rds_sg.id]
  skip_final_snapshot  = true
  tags                 = { Project = "barakat-2025-capstone" }
}

# Secrets Manager for DB creds
resource "aws_secretsmanager_secret" "db_creds" {
  name = "db-creds"
  tags = { Project = "barakat-2025-capstone" }
}

resource "aws_secretsmanager_secret_version" "db_creds_version" {
  secret_id = aws_secretsmanager_secret.db_creds.id
  secret_string = jsonencode({
    mysql_user     = "admin"
    mysql_password = "securepass"
    pg_user        = "admin"
    pg_password    = "securepass"
  })
}

# Bonus: AWS Load Balancer Controller
module "lb_role" {
  source    = "terraform-aws-modules/iam/aws//modules/iam-role-for-service-accounts-eks"
  version   = "~> 5.0"

  role_name                              = "load-balancer-controller"
  attach_load_balancer_controller_policy = true

  oidc_providers = {
    main = {
      provider_arn               = module.eks.oidc_provider_arn
      namespace_service_accounts = ["kube-system:aws-load-balancer-controller"]
    }
  }
}

resource "helm_release" "lb_controller" {
  name       = "aws-load-balancer-controller"
  repository = "https://aws.github.io/eks-charts"
  chart      = "aws-load-balancer-controller"
  namespace  = "kube-system"

  set {
    name  = "clusterName"
    value = module.eks.cluster_name
  }

  set {
    name  = "serviceAccount.create"
    value = "false"
  }

  set {
    name  = "serviceAccount.name"
    value = "aws-load-balancer-controller"
  }
}

# Bonus: External Secrets Operator
resource "helm_release" "external_secrets" {
  name       = "external-secrets"
  repository = "https://charts.external-secrets.io"
  chart      = "external-secrets"
  namespace  = "default"

  set {
    name  = "installCRDs"
    value = "true"
  }
}

module "external_secrets_role" {
  source    = "terraform-aws-modules/iam/aws//modules/iam-role-for-service-accounts-eks"
  version   = "~> 5.0"

  role_name = "external-secrets"
  attach_external_secrets_policy = true
  external_secrets_secrets_manager_arns = [aws_secretsmanager_secret.db_creds.arn]

  oidc_providers = {
    main = {
      provider_arn               = module.eks.oidc_provider_arn
      namespace_service_accounts = ["default:external-secrets"]
    }
  }
}