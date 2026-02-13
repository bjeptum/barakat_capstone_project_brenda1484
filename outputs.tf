# EKS Cluster outputs
output "cluster_endpoint" {
  value       = module.eks.cluster_endpoint
  description = "The endpoint URL for the EKS cluster barakat-2025-capstone-cluster"
}

output "cluster_name" {
  value       = module.eks.cluster_name
  description = "The name of the EKS cluster barakat-2025-capstone-cluster"
}

output "region" {
  value       = "us-east-1"
  description = "AWS region where resources are deployed"
}

# VPC output
output "vpc_id" {
  value       = module.vpc.vpc_id
  description = "The ID of the VPC barakat-2025-capstone-vpc"
}

# S3 Assets Bucket output
output "assets_bucket_name" {
  value       = aws_s3_bucket.assets.bucket
  description = "The name of the S3 bucket storing assets (barakat-assets-1484)"
}

# Terraform backend outputs
output "terraform_state_bucket" {
  value       = "tf-state-barakat-2025-capstone-1484"
  description = "The S3 bucket used for storing Terraform state"
}

output "terraform_lock_table" {
  value       = "tf-lock-barakat-2025-capstone-1484"
  description = "The DynamoDB table used for Terraform state locking"
}

# IAM Developer credentials (sensitive!)
output "dev_access_key_id" {
  value       = aws_iam_access_key.dev_view_key.id
  sensitive   = true
  description = "IAM user barakat-dev-view access key ID (handle securely)"
}

output "dev_secret_key" {
  value       = aws_iam_access_key.dev_view_key.secret
  sensitive   = true
  description = "IAM user barakat-dev-view secret access key (handle securely)"
}

output "dev_console_password" {
  value       = aws_iam_user_login_profile.dev_view_console.password
  sensitive   = true
  description = "IAM user barakat-dev-view console password (handle securely)"
}
