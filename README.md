# Barakat-2025-Capstone Project

## Overview
This capstone project ("Project Barakat") deploys a production-grade Kubernetes environment on AWS EKS for the AWS Retail Store Sample Application.  

**Technologies used**:
- **Terraform** → Infrastructure as Code (VPC, EKS, IAM, S3, Lambda)
- **kubectl** → Direct deployment of official manifest (no Helm)
- **GitHub Actions** → CI/CD pipeline (plan on PR, apply + deploy on merge)
- **Amazon CloudWatch** → Centralized logging (control plane + container logs)
- **S3 + Lambda** → Event-driven serverless image processing

**Key constraints respected**:
- Free-tier friendly (t3.micro nodes, single NAT gateway)
- Region: us-east-1
- Student ID: 1484 (used in bucket names)

**Goal**: Fully automated, observable, secure EKS cluster ready for developer hand-off.

---

## Prerequisites
- AWS account (free tier eligible)
- Tools installed locally:
  - Terraform ≥ 1.9.0
  - AWS CLI v2
  - kubectl
- GitHub repository secrets configured:
  - `AWS_ACCESS_KEY_ID`
  - `AWS_SECRET_ACCESS_KEY`
- Your AWS profile configured with admin credentials

---

## High-Level Architecture
- VPC: project-barakat-vpc (public + private subnets, 2 AZs)
- EKS: barakat-2025-capstone-cluster (1.33, t3.micro nodes)
- App: Retail Store Sample deployed in `retail-app` namespace
- Logging: CloudWatch (control plane + container logs via add-on)
- Serverless: S3 bucket `barakat-assets-1484` → triggers Lambda `barakat-asset-processor`
- CI/CD: GitHub Actions (plan on PR, apply + deploy on merge to main)
- Developer access: IAM user `barakat-dev-view` (ReadOnly + kubectl view)

---

## Deployment Guide

### 1. How to Trigger the Pipeline
The entire deployment is fully automated via **GitHub Actions** (`.github/workflows/terraform.yml`).

**Two ways it runs**:

- **On Pull Request** (to main/master):
  - Triggers `terraform plan`
  - Shows planned changes (review in PR checks)
  - Safe — no apply happens

- **On Merge / Push to main/master**:
  - Triggers `terraform apply -auto-approve`
  - Deploys/updates infrastructure
  - Runs `kubectl apply` of the official retail store manifest

**Manual trigger** (optional):
1. Go to your GitHub repo → **Actions** tab
2. Select the "Terraform CI/CD" workflow
3. Click **Run workflow** (if enabled)

**What gets deployed**:
- VPC, EKS cluster, IAM roles/user, S3 bucket, Lambda
- Retail Store app pods in `retail-app` namespace

---

### 2. Accessing the Retail Store Application

After pipeline completes (or manual `kubectl apply`):

1. Get the LoadBalancer URL:

```
kubectl get svc ui -n retail-app -o jsonpath='{.status.loadBalancer.ingress[0].hostname}{"\n"}'
```

Example output:

```
a8212eea11a8a48858422bd22f421a7a-2017754698.us-east-1.elb.amazonaws.com
```


Open in browser:

```
http://a8212eea11a8a48858422bd22f421a7a-2017754698.us-east-1.elb.amazonaws.com
```

→ You should see the InnovateMart Retail Store UI with products, cart, etc.

**Troubleshooting:**

If URL shows `<pending>` → wait 2–5 minutes (ELB provisioning)

Check pods:

```
kubectl get pods -n retail-app -o wide
```

All should be `Running` / `Ready`.

---

### 3. Verification Checklist (for submission)

Run these after deployment:

#### Infrastructure & App

```
# Cluster running
aws eks describe-cluster --name barakat-2025-capstone-cluster --query "cluster.status"

# Nodes
kubectl get nodes

# Pods healthy
kubectl get pods -n retail-app
```

---

#### Developer Access (barakat-dev-view)

```
# Switch to dev profile
export AWS_PROFILE=barakat-dev

# Update kubeconfig
aws eks update-kubeconfig --name barakat-2025-capstone-cluster --region us-east-1 --profile barakat-dev

# Read access (should succeed)
kubectl get pods -n retail-app
kubectl get nodes

# Write access (should fail)
kubectl delete pod dummy-test -n retail-app --force   # → Forbidden error

# Switch back
unset AWS_PROFILE
```

---

#### Logging

```bash
# Control plane logs (5 groups)
aws logs describe-log-groups --query "logGroups[?contains(logGroupName, 'barakat-2025-capstone-cluster') && contains(logGroupName, '/cluster') || contains(logGroupName, '/api') || contains(logGroupName, '/audit')].logGroupName" --output text

# Container logs (retail-app)
aws logs describe-log-groups --query "logGroups[?contains(logGroupName, 'barakat-2025-capstone-cluster') && contains(logGroupName, 'containerinsights')].logGroupName" --output text
```

---

#### Serverless (S3 + Lambda)

```
# Upload test file
echo "test-$$ (date)" > test-$$(date +%s).jpg
aws s3 cp test-*.jpg s3://barakat-assets-1484/

# Check Lambda logs
aws logs tail /aws/lambda/barakat-asset-processor --since 10m
```

---

### 4. Clean Up (to avoid costs)

```
terraform destroy -auto-approve
```

Warning: This deletes everything 
