# Baraka 2025 Capstone Project

## Overview
This repo implements the InnovateMart EKS deployment for Semester 3 Capstone Project at AltSchool Africa for Cloud Engineering Track. It uses Terraform for IaC, Helm for app, GitHub Actions for CI/CD.

## Setup
1. Set GitHub secrets: AWS_ACCESS_KEY_ID, AWS_SECRET_ACCESS_KEY (OIDC preferred).
2. `terraform init && terraform apply`.

## Pipeline Trigger
- PR to main: Runs `terraform plan`.
- Merge to main: Runs `terraform apply` and optional app deploy.

## App URL
https://project-bedrock-cluster.k8s.nip.io 

## Credentials
bedrock-dev-view:
- CLI Access Key ID: [placeholder - get from Terraform output]
- CLI Secret Key: [placeholder]
- Console Password: [placeholder - reset if needed]

## Testing
- App: `kubectl get pods -n retail-app` (all Running).
- Lambda: Upload file to S3, check CloudWatch logs.
- Logs: Check CloudWatch for control plane and app.
- Dev Access: Use creds for `kubectl get pods` (succeeds), `delete` (fails).

## Destruction
`terraform destroy`.

App from: https://github.com/aws-containers/retail-store-sample-app (use Helm chart).