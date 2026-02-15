terraform {
  backend "s3" {
    bucket         = "tf-state-barakat-2025-capstone-1484"       # S3 state bucket
    key            = "project-bedrock/terraform.tfstate"        # Path inside the bucket for the state file
    region         = "us-east-1"                               
    dynamodb_table = "tf-lock-barakat-2025-capstone-1484"       # DynamoDB table for state locking
    encrypt        = true                                       # Enables encryption at rest
  }
}