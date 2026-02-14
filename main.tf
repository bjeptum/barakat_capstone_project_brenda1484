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
  name = "barakat-2025-capstone-vpc"  # Grading required name
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
  cluster_version = "1.30"
  vpc_id     = module.vpc.vpc_id
  subnet_ids = module.vpc.private_subnets
  cluster_enabled_log_types = ["api", "audit", "authenticator", "controllerManager", "scheduler"]
  cluster_endpoint_public_access = true
  cluster_endpoint_private_access = true
  eks_managed_node_groups = {
    default = {
      min_size       = 1
      max_size       = 1
      desired_size   = 1
      instance_types = ["t3.micro"]
      capacity_type  = "ON_DEMAND"
    }
  }
  cluster_addons = {
    amazon-cloudwatch-observability = {
      most_recent = true
    }
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
  user                    = aws_iam_user.dev_view.name
  password_reset_required = false
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

resource "kubernetes_config_map_v1_data" "aws_auth" {
  metadata {
    name      = "aws-auth"
    namespace = "kube-system"
  }
  data = {
    mapUsers = yamlencode([
      {
        userarn  = "arn:aws:iam::${data.aws_caller_identity.current.account_id}:user/barakat-dev-view"
        username = "barakat-dev-view"
        groups   = ["system:authenticated"]
      }
    ])
  }
}

resource "kubernetes_role_binding" "barakat_dev_view" {
  metadata {
    name      = "barakat-dev-view-binding"
    namespace = "retail-app"
  }
  role_ref {
    api_group = "rbac.authorization.k8s.io"
    kind      = "ClusterRole"
    name      = "view"
  }
  subject {
    kind      = "User"
    name      = "barakat-dev-view"
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

# Bonus: Managed Persistence (RDS)
resource "aws_security_group" "rds_sg" {
  name        = "barakat-rds-sg"
  description = "Allow EKS nodes to access RDS"
  vpc_id      = module.vpc.vpc_id
  ingress {
    from_port       = 3306
    to_port         = 3306
    protocol        = "tcp"
    security_groups = [module.eks.node_security_group_id]
  }
  ingress {
    from_port       = 5432
    to_port         = 5432
    protocol        = "tcp"
    security_groups = [module.eks.node_security_group_id]
  }
  egress {  # Added missing egress
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_db_subnet_group" "main" {
  name       = "barakat-db-subnet-group"
  subnet_ids = module.vpc.private_subnets
}

# Secrets Manager for credentials
resource "aws_secretsmanager_secret" "db_creds" {
  name = "barakat-db-creds"
}

resource "aws_secretsmanager_secret_version" "db_creds" {
  secret_id = aws_secretsmanager_secret.db_creds.id
  secret_string = jsonencode({
    username = "admin"  # generate dynamically in real
    password = "StrongPassword123!"
  })
}

# MySQL Catalog
resource "aws_db_instance" "mysql_catalog" {
  identifier             = "barakat-catalog-db"  # Fixed naming
  allocated_storage      = 20
  engine                 = "mysql"
  instance_class         = "db.t3.micro"
  db_name                = "catalog"
  username               = jsondecode(aws_secretsmanager_secret_version.db_creds.secret_string)["username"] # Uses secrets
  password               = jsondecode(aws_secretsmanager_secret_version.db_creds.secret_string)["password"] # Uses secrets
  db_subnet_group_name   = aws_db_subnet_group.main.name
  vpc_security_group_ids = [aws_security_group.rds_sg.id]
  skip_final_snapshot    = true
  publicly_accessible    = false  # Added for security/cost
  multi_az               = false  # Added for cost
}

# PostgreSQL Orders
resource "aws_db_instance" "postgres_orders" {
  identifier             = "barakat-orders-db"
  allocated_storage      = 20
  engine                 = "postgres"
  instance_class         = "db.t3.micro"
  db_name                = "orders"
  username               = jsondecode(aws_secretsmanager_secret_version.db_creds.secret_string)["username"] # Uses secrets
  password               = jsondecode(aws_secretsmanager_secret_version.db_creds.secret_string)["password"] # Uses secrets
  db_subnet_group_name   = aws_db_subnet_group.main.name
  vpc_security_group_ids = [aws_security_group.rds_sg.id]
  skip_final_snapshot    = true
  publicly_accessible    = false
  multi_az               = false
}

# Bonus: Advanced Networking ALB
module "lb_controller_irsa" {
  source  = "terraform-aws-modules/iam/aws//modules/iam-role-for-service-accounts-eks"
  version = "~> 5.35"
  role_name = "barakat-alb-controller"
  attach_load_balancer_controller_policy = true
  oidc_providers = {
    main = {
      provider_arn = module.eks.oidc_provider_arn
      namespace_service_accounts = ["kube-system:aws-load-balancer-controller"]
    }
  }
}

resource "kubernetes_service_account" "alb_controller" {
  metadata {
    name      = "aws-load-balancer-controller"
    namespace = "kube-system"
    annotations = {
      "eks.amazonaws.com/role-arn" = module.lb_controller_irsa.iam_role_arn
    }
  }
}

resource "helm_release" "alb_controller" {
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