# CI/CD Pipeline Workshop - Deployment Guide

A standalone, hands-on workshop demonstrating AWS DevOps Agent's autonomous investigation capabilities across a full CI/CD deployment pipeline. Five labs inject realistic failures at every pipeline stage — build, test, deploy, post-deploy, and IAM permissions — then showcase how DevOps Agent correlates CodePipeline events, CodeBuild logs, CodeDeploy health checks, ALB metrics, and CloudTrail to identify root causes.

---

## Overview

This demo deploys a complete CI/CD pipeline with a Flask web application:

| Component | What's Deployed | Details |
|-----------|----------------|---------|
| VPC | Full networking stack | 10.0.0.0/16 CIDR, 2 public subnets, IGW, route table |
| ALB | Application Load Balancer | Internet-facing, port 80 → 5000, /health check |
| EC2 ASG | Auto Scaling Group | 2x t3.micro, Amazon Linux 2023, CodeDeploy agent |
| CodePipeline | 4-stage pipeline | Source (S3) → Build → Test → Deploy |
| CodeBuild | 2 build projects | Build (pip install + compile) and Test (unittest) |
| CodeDeploy | Application + Deployment Group | AllAtOnce strategy, auto-rollback on failure/alarm |
| S3 | Versioned artifact bucket | Source code + build artifacts |
| CloudWatch | 8 alarms | Build/test/pipeline/deploy failures, ALB unhealthy/5xx/latency, CPU |
| SNS | 2 topics | Alarm notifications + pipeline event notifications |
| IAM | 5 roles | EC2, CodeBuild, CodeDeploy, CodePipeline, source packager |

**Total CloudFormation Resources:** 39  
**Deploy Time:** ~10-15 minutes  
**Estimated Cost:** ~$2-3/hour  
**Discovery Tag:** `devopsagent = true`

### Application

Flask web app served by gunicorn (2 workers, port 5000):

| Endpoint | Method | Purpose |
|----------|--------|---------|
| `/health` | GET | ALB health check + instance identification |
| `/` | GET | Service info (name, version, hostname) |
| `/api/status` | GET | Operational status |
| `/api/process` | POST | Data processing (accepts JSON body) |

---

## Prerequisites

### Required Tools

| Tool | Version | Verify Command |
|------|---------|----------------|
| AWS CLI | v2.x | `aws --version` |
| bash | 4.x+ | `bash --version` |
| curl | any | `curl --version` |
| zip | any | `zip --version` |

### AWS Permissions

The deploying IAM user/role needs:

```
iam:CreateRole, iam:PutRolePolicy, iam:AttachRolePolicy, iam:PassRole,
iam:GetRole, iam:GetRolePolicy, iam:DeleteRole, iam:DeleteRolePolicy,
iam:DetachRolePolicy, iam:CreateInstanceProfile, iam:AddRoleToInstanceProfile,
iam:RemoveRoleFromInstanceProfile, iam:DeleteInstanceProfile

ec2:CreateVpc, ec2:CreateSubnet, ec2:CreateInternetGateway, ec2:CreateRouteTable,
ec2:CreateRoute, ec2:CreateSecurityGroup, ec2:AuthorizeSecurityGroupIngress,
ec2:CreateLaunchTemplate, ec2:DescribeInstances, ec2:RunInstances

elasticloadbalancing:CreateLoadBalancer, elasticloadbalancing:CreateTargetGroup,
elasticloadbalancing:CreateListener, elasticloadbalancing:DescribeTargetHealth

autoscaling:CreateAutoScalingGroup, autoscaling:UpdateAutoScalingGroup

codepipeline:CreatePipeline, codepipeline:GetPipelineState, codepipeline:StartPipelineExecution
codebuild:CreateProject, codebuild:StartBuild, codebuild:BatchGetBuilds
codedeploy:CreateApplication, codedeploy:CreateDeploymentGroup, codedeploy:CreateDeployment

s3:CreateBucket, s3:PutObject, s3:GetObject, s3:DeleteObject, s3:ListBucket,
s3:PutBucketVersioning, s3:GetBucketVersioning, s3:ListObjectVersions,
s3:DeleteObjectVersion

sns:*, cloudwatch:*, cloudformation:*, logs:*, lambda:*,
codestar-notifications:CreateNotificationRule
```

### DevOps Agent Space Setup

1. Navigate to the [AWS DevOps Agent console](https://console.aws.amazon.com/devops-agent/)
2. Create or select an Agent Space
3. Add the target AWS account as a monitored account
4. Configure tag-based resource discovery: `devopsagent = true`
5. Ensure access to:
   - CloudWatch Metrics (CodeBuild, CodePipeline, CodeDeploy, ApplicationELB, EC2 namespaces)
   - CloudWatch Logs (`/aws/codebuild/{prefix}-build` and `/aws/codebuild/{prefix}-test`)
   - CloudTrail (IAM policy changes, pipeline executions, deployments)
6. (Optional) Connect CodePipeline state change events to Agent Space

### Recommended

- **Region:** `us-east-1` (default, all services available)
- **CloudTrail:** Enabled for IAM policy changes (`PutRolePolicy`), CodePipeline executions, CodeDeploy deployments

---

## Folder Structure

```
cicd-pipeline-workshop/
├── DEPLOYMENT_GUIDE.md              ← This file
├── README.md                         ← Architecture details and lab descriptions
├── cloudformation/
│   └── cicd-workshop.yaml            ← 39 resources (VPC, ALB, EC2, Pipeline, Build, Deploy)
├── labs/
│   ├── lab1-build-failure/
│   │   ├── inject.sh                 ← Adds nonexistent pip package to requirements.txt
│   │   ├── rollback.sh              ← Restores original source and triggers pipeline
│   │   └── README.md
│   ├── lab2-test-failure/
│   │   ├── inject.sh                 ← Introduces 2 API regression bugs caught by tests
│   │   ├── rollback.sh
│   │   └── README.md
│   ├── lab3-deploy-health-check/
│   │   ├── inject.sh                 ← Start script uses wrong port (8080 vs 5000)
│   │   ├── rollback.sh
│   │   └── README.md
│   ├── lab4-post-deploy-regression/
│   │   ├── inject.sh                 ← Adds time.sleep() delays to all endpoints
│   │   ├── rollback.sh
│   │   └── README.md
│   └── lab5-pipeline-permission/
│       ├── inject.sh                 ← Adds explicit S3 Deny to CodeBuild IAM role
│       ├── rollback.sh              ← Restores S3 Allow permissions
│       └── README.md
├── scripts/
│   ├── deploy.sh                     ← CloudFormation deploy + initial pipeline trigger
│   ├── cleanup.sh                    ← S3 bucket empty + stack deletion
│   └── generate-traffic.sh           ← Sends HTTP requests to ALB endpoints
└── tests/
    └── validate-stack.sh             ← Verifies VPC, ALB, ASG, pipeline, alarms
```

---

## Step-by-Step Deployment

### Step 1: Navigate to the Workshop Directory

```bash
cd cicd-pipeline-workshop
```

### Step 2: Verify AWS Credentials

```bash
aws sts get-caller-identity
```

Expected output shows your Account, UserId, and Arn. If this fails, run `aws configure` first.

### Step 3: Make Scripts Executable

```bash
chmod +x scripts/*.sh
chmod +x labs/*/inject.sh labs/*/rollback.sh
```

### Step 4: Deploy the CloudFormation Stack

```bash
# Default deployment (stack: devops-agent-cicd, region: us-east-1)
./scripts/deploy.sh

# OR with custom stack name and alarm email notifications
./scripts/deploy.sh my-cicd-demo user@example.com

# OR in a specific region
export AWS_REGION=us-west-2
./scripts/deploy.sh
```

The deploy script will:
1. Validate the CloudFormation template syntax
2. Deploy the stack with `CAPABILITY_NAMED_IAM`
3. Tag all resources with `devopsagent=true`
4. Print all stack outputs (ALB endpoint, pipeline name, CodeBuild/CodeDeploy names)
5. Wait for EC2 instances to pass ALB health checks (up to 10 minutes)
6. Trigger the initial pipeline execution
7. Custom resource Lambda packages the Flask app and uploads `source/app.zip` to S3

**Expected duration:** 10-15 minutes (includes EC2 boot, CodeDeploy agent install, first pipeline run)

### Step 5: Wait for Initial Pipeline to Complete

```bash
# Monitor pipeline status
aws codepipeline get-pipeline-state \
    --name devops-agent-cicd-pipeline \
    --query 'stageStates[*].{Stage:stageName,Status:latestExecution.status}' \
    --output table
```

Wait until all 4 stages show `Succeeded` (~5 minutes after deploy completes).

### Step 6: Validate the Deployment

```bash
./tests/validate-stack.sh devops-agent-cicd
```

This checks:
- Stack status
- VPC and networking
- ALB endpoint responds with HTTP 200
- ASG has 2 healthy instances
- CodePipeline exists and has completed
- CodeBuild projects exist
- CodeDeploy application and deployment group exist
- S3 source artifact (`source/app.zip`) exists
- 8 CloudWatch alarms exist
- End-to-end ALB health check passes

### Step 7: Note the ALB Endpoint

```bash
aws cloudformation describe-stacks \
    --stack-name devops-agent-cicd \
    --query 'Stacks[0].Outputs[?OutputKey==`ALBEndpoint`].OutputValue' \
    --output text
```

Test it:
```bash
curl -s http://<ALB-DNS>/health | python3 -m json.tool
curl -s http://<ALB-DNS>/api/status | python3 -m json.tool
```

---

## Executing the Labs

### Recommended Order

1. **Lab 1** (Build Failure) — simplest, fastest feedback (~2 min to failure)
2. **Lab 2** (Test Failure) — builds on Lab 1, multi-stage analysis
3. **Lab 5** (Pipeline Permission) — IAM-focused, CloudTrail correlation
4. **Lab 3** (Deploy Health Check) — full pipeline run + ALB monitoring
5. **Lab 4** (Post-Deploy Regression) — most complex, all stages pass

---

### Lab 1: Build Failure (Beginner)

**What Gets Broken:** `nonexistent-package-xyz==99.99.99` added to requirements.txt  
**Pipeline Result:** Build stage FAILS  
**Alarms Triggered:** `build-failures`, `pipeline-failures`

**Steps:**

```bash
# 1. Navigate to the lab
cd labs/lab1-build-failure/

# 2. Inject the failure (uploads broken source, triggers pipeline)
./inject.sh devops-agent-cicd

# 3. Monitor the pipeline (failure appears in ~2-3 minutes)
aws codepipeline get-pipeline-state \
    --name devops-agent-cicd-pipeline \
    --query 'stageStates[*].{Stage:stageName,Status:latestExecution.status}' \
    --output table

# 4. Check CodeBuild logs for the error
aws logs tail /aws/codebuild/devops-agent-cicd-build --since 5m | grep -i "error\|ERROR"

# 5. Wait for alarms (~5 minutes)
aws cloudwatch describe-alarms \
    --alarm-name-prefix devops-agent-cicd \
    --state-value ALARM \
    --query 'MetricAlarms[*].[AlarmName,StateValue]' \
    --output table

# 6. Investigate with DevOps Agent
# Ask: "Why did the CI/CD pipeline build stage fail?"
# OR: "Investigate the CodeBuild failure for devops-agent-cicd-build"

# 7. Expected findings:
#   - CodeBuild build failure at install phase
#   - pip error: "Could not find a version that satisfies the requirement nonexistent-package-xyz"
#   - Source artifact change detected
#   - Recommendation: Remove invalid package from requirements.txt

# 8. Rollback (restores original source, triggers pipeline)
./rollback.sh devops-agent-cicd
```

---

### Lab 2: Test Failure (Beginner)

**What Gets Broken:** App code has 2 regression bugs: `/api/status` returns `'degraded'` instead of `'operational'`, `/api/process` drops the `'processed'` field  
**Pipeline Result:** Build OK → Test FAILS  
**Alarms Triggered:** `test-failures`, `pipeline-failures`

**Steps:**

```bash
# 1. Navigate to the lab
cd labs/lab2-test-failure/

# 2. Inject the failure
./inject.sh devops-agent-cicd

# 3. Monitor pipeline - Build passes, Test fails (~5 minutes)
aws codepipeline get-pipeline-state \
    --name devops-agent-cicd-pipeline \
    --query 'stageStates[*].{Stage:stageName,Status:latestExecution.status}' \
    --output table

# 4. Check test output in CodeBuild logs
aws logs tail /aws/codebuild/devops-agent-cicd-test --since 5m | grep -i "fail\|FAIL\|assert"

# 5. Investigate with DevOps Agent
# Ask: "The CI/CD pipeline test stage is failing. What tests are broken and why?"
# OR: "Investigate test failures in devops-agent-cicd pipeline"

# 6. Expected findings:
#   - test_status_is_operational: AssertionError ('degraded' != 'operational')
#   - test_process_returns_processed_flag: KeyError ('processed')
#   - Two regression bugs introduced in code change
#   - Build passed (code compiles) but tests caught contract violations

# 7. Rollback
./rollback.sh devops-agent-cicd
```

---

### Lab 3: Deploy Health Check Failure (Intermediate)

**What Gets Broken:** appspec.yml references `start_server_broken.sh` which starts gunicorn on port **8080** instead of **5000**. ALB health check on port 5000 fails.  
**Pipeline Result:** Build OK → Test OK → Deploy FAILS (auto-rollback)  
**Alarms Triggered:** `alb-unhealthy`, `deploy-failures`

**Steps:**

```bash
# 1. Navigate to the lab
cd labs/lab3-deploy-health-check/

# 2. Inject the failure
./inject.sh devops-agent-cicd

# 3. Monitor pipeline - Build and Test pass, Deploy fails (~8 minutes)
aws codepipeline get-pipeline-state \
    --name devops-agent-cicd-pipeline \
    --query 'stageStates[*].{Stage:stageName,Status:latestExecution.status}' \
    --output table

# 4. Watch CodeDeploy deployment status
aws deploy list-deployments \
    --application-name devops-agent-cicd-app \
    --deployment-group-name devops-agent-cicd-dg \
    --query 'deployments[0]' \
    --output text | xargs -I {} aws deploy get-deployment --deployment-id {} \
    --query 'deploymentInfo.{Status:status,ErrorInfo:errorInformation}' \
    --output table

# 5. Check ALB target health
aws elbv2 describe-target-health \
    --target-group-arn $(aws elbv2 describe-target-groups \
        --names devops-agent-cicd-tg \
        --query 'TargetGroups[0].TargetGroupArn' \
        --output text) \
    --query 'TargetHealthDescriptions[*].{Target:Target.Id,Health:TargetHealth.State}' \
    --output table

# 6. Investigate with DevOps Agent
# Ask: "CodeDeploy deployment failed and rolled back. Why are instances unhealthy?"
# OR: "Investigate the deployment failure on devops-agent-cicd"

# 7. Expected findings:
#   - Application started on port 8080 but ALB health check targets port 5000
#   - CodeDeploy ValidateService passes (checks localhost:8080)
#   - But ALB marks instances unhealthy (port 5000 not responding)
#   - Auto-rollback triggered by alb-unhealthy alarm
#   - Port mismatch between start script and ALB target group configuration

# 8. Rollback
./rollback.sh devops-agent-cicd
```

---

### Lab 4: Post-Deploy Performance Regression (Advanced)

**What Gets Broken:** `time.sleep()` added to all endpoints (3-5 seconds) EXCEPT `/health`  
**Pipeline Result:** All 4 stages PASS (health checks pass since /health has no delay)  
**Alarms Triggered:** `alb-latency` (after traffic generation)

This is the most realistic scenario — a deploy that passes all checks but degrades production performance.

**Steps:**

```bash
# 1. Navigate to the lab
cd labs/lab4-post-deploy-regression/

# 2. Inject the failure
./inject.sh devops-agent-cicd

# 3. Wait for pipeline to complete SUCCESSFULLY (~8 minutes)
# All stages will pass because /health has no sleep!
aws codepipeline get-pipeline-state \
    --name devops-agent-cicd-pipeline \
    --query 'stageStates[*].{Stage:stageName,Status:latestExecution.status}' \
    --output table

# 4. Generate traffic to trigger the latency alarm
../../scripts/generate-traffic.sh devops-agent-cicd 30 1
# You'll notice responses take 3-5 seconds each

# 5. Wait 3-5 minutes for latency alarm
aws cloudwatch describe-alarms \
    --alarm-name-prefix devops-agent-cicd \
    --state-value ALARM \
    --query 'MetricAlarms[*].[AlarmName,StateValue]' \
    --output table
# Expected: alb-latency in ALARM

# 6. Investigate with DevOps Agent
# Ask: "Application latency has spiked after a deployment. All pipeline checks passed. What changed?"
# OR: "Investigate the ALB latency alarm. Recent deployment completed successfully."

# 7. Expected findings:
#   - TargetResponseTime metric spiked from ~100ms to ~3-5s
#   - Spike correlates with deployment timestamp
#   - Health checks pass (no errors, just latency)
#   - Code change introduced artificial delays on non-health endpoints
#   - Recommendation: Add latency assertions to tests, or canary deployment with latency monitoring

# 8. Rollback
./rollback.sh devops-agent-cicd
```

---

### Lab 5: Pipeline Permission Issue (Advanced)

**What Gets Broken:** CodeBuild IAM role's inline policy replaced with one that has an explicit `Deny` on S3 actions  
**Pipeline Result:** Build FAILS with AccessDenied  
**Alarms Triggered:** `build-failures`, `pipeline-failures`

**Steps:**

```bash
# 1. Navigate to the lab
cd labs/lab5-pipeline-permission/

# 2. Inject the failure
./inject.sh devops-agent-cicd

# 3. Monitor pipeline - Build fails with AccessDenied (~2 minutes)
aws codepipeline get-pipeline-state \
    --name devops-agent-cicd-pipeline \
    --query 'stageStates[*].{Stage:stageName,Status:latestExecution.status}' \
    --output table

# 4. Check CodeBuild logs for AccessDenied
aws logs tail /aws/codebuild/devops-agent-cicd-build --since 5m | grep -i "access\|denied\|error"

# 5. Investigate with DevOps Agent
# Ask: "CodeBuild is failing with AccessDenied. What happened to the permissions?"
# OR: "Pipeline build stage fails with S3 access denied. Investigate."

# 6. Expected findings:
#   - CodeBuild cannot download source from S3 (AccessDenied)
#   - IAM policy change detected on CodeBuild role via CloudTrail
#   - Explicit Deny on s3:GetObject and s3:PutObject added
#   - Recommendation: Remove Deny statement, restore S3 access

# 7. Rollback (restores IAM policy directly)
./rollback.sh devops-agent-cicd
```

---

## Generating Traffic

The `generate-traffic.sh` script sends HTTP requests to the ALB:

```bash
# Usage: ./scripts/generate-traffic.sh [stack-name] [count] [interval-seconds]

# Default: 20 requests, 2s apart
./scripts/generate-traffic.sh devops-agent-cicd

# Heavy load: 30 requests, 1s apart
./scripts/generate-traffic.sh devops-agent-cicd 30 1

# Quick test: 5 requests, 3s apart
./scripts/generate-traffic.sh devops-agent-cicd 5 3
```

The script hits these endpoints:
- `GET /health`
- `GET /`
- `GET /api/status`
- `POST /api/process` (with JSON body)

---

## Cost Estimate

| Service | Cost Driver | Estimate |
|---------|------------|----------|
| EC2 | 2x t3.micro (on-demand) | ~$1.04/hr |
| ALB | Load balancer hour + LCU | ~$0.50/hr |
| CodeBuild | Build minutes (general1.small, ~$0.005/min) | ~$0.01/build |
| S3 | Artifact storage (versioned) | ~$0.01/hr |
| CloudWatch | 8 alarms + log storage | ~$0.10/hr |
| **Total** | | **~$2-3/hr** |

**Important:** Run `cleanup.sh` when done. EC2 instances and ALB bill continuously.

---

## Cleanup

```bash
./scripts/cleanup.sh devops-agent-cicd
```

The script will:
1. Prompt for confirmation (y/N)
2. Empty the S3 artifact bucket (all objects, versions, and delete markers)
3. Delete the CloudFormation stack
4. Wait for stack deletion to complete

### Verify Cleanup

```bash
aws cloudformation describe-stacks --stack-name devops-agent-cicd 2>&1 | \
    grep -q "does not exist" && echo "Clean" || echo "Stack still exists"
```

---

## Troubleshooting

| Problem | Solution |
|---------|----------|
| EC2 instances not registering with ALB | Wait 5 minutes for boot + CodeDeploy agent install; check EC2 SG allows port 5000 from ALB SG |
| Pipeline not starting | Verify `source/app.zip` exists in S3 bucket; custom resource should create it on deploy |
| CodeDeploy agent not running | Connect via SSM Session Manager: `sudo systemctl status codedeploy-agent` |
| First pipeline run fails | EC2 instances may not be ready; wait for ALB healthy targets, then retry: `aws codepipeline start-pipeline-execution --name devops-agent-cicd-pipeline` |
| Build fails with AccessDenied (not Lab 5) | Check CodeBuild role has S3 permissions; verify artifact bucket name matches |
| Deploy rolls back immediately | Check ALB target health; verify start script uses port 5000; check /health endpoint |
| Rollback doesn't restore clean state | Labs 2-4 rollback uploads original source + triggers pipeline; Lab 5 restores IAM directly |
| Alarms stay in ALARM after rollback | Wait 1-2 evaluation periods (5 min); run traffic to generate healthy data points |
| Stack deletion fails (bucket not empty) | The cleanup script handles this automatically; if manual: `aws s3 rm s3://[bucket] --recursive` then delete versions |
| Stack fails with IAM error | Ensure deploying user has `iam:CreateRole` and `iam:PutRolePolicy` |

### Manual Pipeline Check

```bash
# Get pipeline status
aws codepipeline get-pipeline-state \
    --name devops-agent-cicd-pipeline \
    --query 'stageStates[*].{Stage:stageName,Status:latestExecution.status}' \
    --output table

# Retry pipeline manually
aws codepipeline start-pipeline-execution \
    --name devops-agent-cicd-pipeline
```

### Manual ALB Health Check

```bash
ALB_ENDPOINT=$(aws cloudformation describe-stacks \
    --stack-name devops-agent-cicd \
    --query 'Stacks[0].Outputs[?OutputKey==`ALBEndpoint`].OutputValue' \
    --output text)

curl -s "${ALB_ENDPOINT}/health" | python3 -m json.tool
curl -s "${ALB_ENDPOINT}/api/status" | python3 -m json.tool
```

### Checking CodeBuild Logs

```bash
# Build logs
aws logs tail /aws/codebuild/devops-agent-cicd-build --since 10m

# Test logs
aws logs tail /aws/codebuild/devops-agent-cicd-test --since 10m
```
