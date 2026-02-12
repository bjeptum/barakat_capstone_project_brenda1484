terraform {
  backend "s3" {
    bucket         = "your-tf-state-bucket"  # Manually created
    key            = "bedrock/terraform.tfstate"
    region         = "us-east-1"
    dynamodb_table = "tf-lock"  # Manually created
  }
}