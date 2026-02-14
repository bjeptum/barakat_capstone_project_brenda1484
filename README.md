# Barakat-2025-Capstone Project

## Overview
This capstone project sets up a production-grade Kubernetes environment on AWS EKS for a retail e-commerce app. Uses Terraform for IaC, Helm for app deployment, GitHub Actions for CI/CD, CloudWatch for logging, S3+Lambda for serverless.

Goal: Secure, scalable, cost-optimized (t3.micro, single NAT, destroy after).

## Prerequisites
- AWS account (free tier).
- Terraform v1.5+, kubectl, Helm, AWS CLI.
- GitHub repo with secrets: AWS_ACCESS_KEY_ID, AWS_SECRET_ACCESS_KEY.
- Student ID: 1484 (for buckets)( My Student ID)

## High-Level Plan
1. Terraform infrastructure.
2. Deploy app on EKS.
3. Secure developer access.
4. Logging.
5. S3 + Lambda.
6. CI/CD.
7. Bonuses (RDS, ALB).
8. Deliverables.

## Cost Optimization
- EKS: 1 t3.micro node, min/max=1.
- Single NAT.
- RDS: db.t3.micro, no multi-AZ, private.
- Destroy after: terraform destroy.

Expected: $4-12 for 24-48h.

## Infrastructure Setup
Run: terraform init, plan, apply.

## CI/CD Automation
GitHub Actions: PR → plan, merge → apply + deploy.

Secrets: AWS creds.

Verification: Create PR (plan runs), merge (apply runs).

## Bonus: Managed Persistence (RDS)
Replaces in-cluster DBs with RDS MySQL/Postgres, secrets in Secrets Manager.

Install External Secrets Operator: helm install external-secrets external-secrets/external-secrets -n external-secrets --create-namespace

Create SecretStore and ExternalSecret YAMLs (as in solution).

Update Helm values.yaml: catalog.db.host = RDS endpoint, secretName = db-creds.

## Bonus: Advanced Networking (ALB)
Exposes UI with ALB, HTTPS via ACM (use nip.io).

Request ACM cert: aws acm request-certificate --domain-name "*.barakat-1484.nip.io" --validation-method DNS --region us-east-1

Apply ingress.yaml.

App URL: https://barakat-1484.nip.io (submit if done).

## Deliverables
- Tagging: All with Project: barakat-2025-capstone.
- Git Repo: https://github.com/bjeptum/barakat_capstone_project_brenda1484
- Architecture Diagram: architecture_diagram.png
- Deployment Guide: See above.
- Trigger: PR/merge as above.
- App URL: 
- Credentials: CLI Access Key ID: [from output], Secret: [from output]; Console Password: [from output].
- Grading Data: grading.json (run terraform output -json > grading.json)

## Verification
- App: kubectl get pods -n retail-app
- Lambda: Upload to S3, check CloudWatch.
- Dev Access: kubectl get (works), delete (fails).
- Logs: CloudWatch groups.

## Clean Up
terraform destroy to avoid costs.