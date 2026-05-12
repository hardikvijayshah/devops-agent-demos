# Proactive Evaluations Workshop - Deployment Guide

**The ONLY demo showcasing AWS DevOps Agent's proactive Evaluation (prevention) capabilities.**

Unlike reactive investigation workshops, this demo deploys **intentionally under-monitored and misconfigured infrastructure**, then uses DevOps Agent's Evaluation mode to discover observability gaps, capacity risks, resilience weaknesses, deployment safety issues, and security posture problems — all **before** any incident occurs.

---

## Overview

This demo deploys infrastructure with intentional gaps across 5 categories:

| Component | What's Deployed | Intentional Gap |
|-----------|----------------|-----------------|
| API Gateway | REST API (POST /orders, GET /inventory) | No auth, no WAF, no throttling, no validation |
| Lambda (x3) | order-processor, inventory-checker, session-cleanup | No DLQ, no X-Ray, no reserved concurrency, 300s timeout |
| DynamoDB (x3) | Orders, Inventory, Sessions tables | No auto-scaling, low provisioned throughput |
| ALB + ASG | 2x t3.micro instances (fixed) | No scaling policy, Min=Max=2 |
| CloudWatch | Only 3 alarms (should be 10+) | Lenient thresholds (Lambda errors >= 50, API 5xx >= 100) |
| SNS | Notification + Alarm topics | No encryption |
| EventBridge | Scheduled inventory check + session cleanup | Redundant cleanup (TTL exists) |

**Total CloudFormation Resources:** 35  
**Deploy Time:** ~5-10 minutes  
**Estimated Cost:** ~$2/hour  

---

## Prerequisites

### Required Tools

| Tool | Version | Verify Command |
|------|---------|----------------|
| AWS CLI | v2.x | `aws --version` |
| bash | 4.x+ | `bash --version` |
| curl | any | `curl --version` |

### AWS Permissions

The deploying IAM user/role needs:

```
iam:CreateRole, iam:PutRolePolicy, iam:AttachRolePolicy, iam:CreateInstanceProfile,
iam:AddRoleToInstanceProfile, iam:PassRole, iam:GetRole, iam:DeleteRole,
iam:DeleteRolePolicy, iam:DetachRolePolicy, iam:RemoveRoleFromInstanceProfile,
iam:DeleteInstanceProfile

ec2:CreateVpc, ec2:CreateSubnet, ec2:CreateInternetGateway, ec2:CreateRouteTable,
ec2:CreateRoute, ec2:CreateSecurityGroup, ec2:AuthorizeSecurityGroupIngress,
ec2:CreateLaunchTemplate, ec2:DescribeInstances, ec2:RunInstances

elasticloadbalancing:CreateLoadBalancer, elasticloadbalancing:CreateTargetGroup,
elasticloadbalancing:CreateListener, elasticloadbalancing:RegisterTargets

autoscaling:CreateAutoScalingGroup, autoscaling:UpdateAutoScalingGroup

apigateway:*, lambda:*, dynamodb:*, sns:*, events:*, cloudwatch:*,
cloudformation:*, logs:*, ssm:GetParameter
```

### DevOps Agent Space

1. Agent Space configured in your AWS account
2. **Tag-based discovery** enabled with filter: `devopsagent = true`
3. **Evaluations mode enabled** (this is separate from Investigations)
4. CloudWatch Logs, Metrics, and CloudTrail access configured

### Recommended

- **Region:** `us-east-1` (all services available)
- **CloudTrail:** Enabled for configuration change detection

---

## Folder Structure

```
proactive-evaluations-workshop/
├── DEPLOYMENT_GUIDE.md              ← This file
├── README.md                         ← Workshop overview and architecture
├── cloudformation/
│   └── evaluations-workshop.yaml     ← 35 resources (all with intentional gaps)
├── labs/
│   ├── lab1-observability-gaps/
│   │   ├── inject.sh                 ← Generates traffic to make metric gaps visible
│   │   ├── rollback.sh              ← No changes to revert (gaps are by design)
│   │   └── README.md
│   ├── lab2-capacity-planning/
│   │   ├── inject.sh                 ← Burst traffic to stress provisioned capacity
│   │   ├── rollback.sh
│   │   └── README.md
│   ├── lab3-resilience-weaknesses/
│   │   ├── inject.sh                 ← Malformed requests exposing missing validation
│   │   ├── rollback.sh
│   │   └── README.md
│   ├── lab4-deployment-safety/
│   │   ├── inject.sh                 ← Deploys broken code (no rollback exists)
│   │   ├── rollback.sh              ← Manual restore (proves the gap)
│   │   └── README.md
│   └── lab5-security-posture/
│       ├── inject.sh                 ← Demonstrates unauthenticated access/abuse
│       ├── rollback.sh
│       └── README.md
├── scripts/
│   ├── deploy.sh                     ← CloudFormation deploy
│   ├── cleanup.sh                    ← Stack deletion
│   └── generate-traffic.sh           ← Order + inventory requests
└── tests/
    └── validate-stack.sh             ← Verifies resources + intentional gaps exist
```

---

## Key Differences from Reactive Workshops

| Aspect | Reactive (Serverless/CI/CD) | Proactive (This Workshop) |
|--------|----------------------------|---------------------------|
| **Agent Mode** | Investigation | Evaluation |
| **Trigger** | CloudWatch Alarm fires | Scheduled (weekly) or on-demand |
| **Goal** | Find root cause of active problem | Prevent future problems |
| **Inject scripts** | Break something specific | Generate traffic to make gaps visible |
| **Output** | Mitigation plan | Recommendations in Ops Backlog |
| **Alarms needed?** | Yes, alarms must fire | No — agent analyzes configuration directly |

---

## Step-by-Step Deployment

### Step 1: Navigate to the Workshop Directory

```bash
cd proactive-evaluations-workshop
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
# Default deployment (stack: devops-eval, region: us-east-1)
./scripts/deploy.sh

# OR with custom stack name and alarm email
./scripts/deploy.sh my-eval-workshop user@example.com

# OR in a specific region
export AWS_REGION=us-west-2
./scripts/deploy.sh
```

The deploy script will:
1. Validate the CloudFormation template
2. Deploy the stack with `CAPABILITY_NAMED_IAM`
3. Wait for ALB health checks to pass
4. Test the API Gateway endpoint
5. Print all stack outputs

**Expected duration:** 5-10 minutes

### Step 5: Validate the Deployment

```bash
./tests/validate-stack.sh devops-eval
```

This verifies:
- Stack status (CREATE_COMPLETE)
- All Lambda functions are Active
- DynamoDB tables are ACTIVE
- API Gateway responds
- ALB is healthy
- Seed data (8 inventory items) is populated
- Only 3 CloudWatch alarms exist (confirms intentional gap)

### Step 6: Note the Outputs

```bash
aws cloudformation describe-stacks \
    --stack-name devops-eval \
    --query 'Stacks[0].Outputs[*].[OutputKey,OutputValue]' \
    --output table
```

Save these values:
- **ApiEndpoint** - API Gateway URL (e.g., `https://xxxxx.execute-api.us-east-1.amazonaws.com/prod`)
- **ALBEndpoint** - ALB DNS (e.g., `http://devops-eval-alb-xxxxx.us-east-1.elb.amazonaws.com`)

---

## Executing the Labs

### Lab 1: Observability Gaps (Beginner)

**Focus:** Missing alarms, lenient thresholds, no tracing

**What DevOps Agent Should Discover:**
- 8+ missing CloudWatch alarms (DynamoDB throttle, Lambda duration, Lambda throttle, ALB latency, API latency, ASG CPU, request anomaly, DLQ)
- Existing alarm thresholds too lenient (Lambda errors >= 50 should be ~5, API 5xx >= 100 should be ~10)
- No X-Ray tracing on Lambda functions
- No detailed metrics enabled on API Gateway

**Steps:**

```bash
# 1. Navigate to the lab
cd labs/lab1-observability-gaps/

# 2. Generate traffic to produce metrics (makes gaps visible)
./inject.sh devops-eval

# 3. Wait 5 minutes for metrics to aggregate in CloudWatch

# 4. Verify only 3 alarms exist (should be 10+)
aws cloudwatch describe-alarms \
    --alarm-name-prefix devops-eval \
    --query 'length(MetricAlarms)' \
    --output text

# 5. Trigger DevOps Agent Evaluation
# Via Web UI: Agent Space → Evaluations → Create New Evaluation
# Title: "Evaluate observability posture for devops-eval resources"
# Scope: Resources tagged devopsagent=true
#
# OR via Slack:
# "Evaluate the monitoring and observability of resources tagged devopsagent=true"

# 6. Review recommendations in the Ops Backlog
# The agent will recommend:
#   - Adding DynamoDB throttle alarm
#   - Adding Lambda duration/concurrency alarms
#   - Adding ALB latency alarm
#   - Tightening existing alarm thresholds
#   - Enabling X-Ray tracing

# 7. No rollback needed (gaps are by design)
./rollback.sh devops-eval
```

---

### Lab 2: Capacity Planning (Intermediate)

**Focus:** Auto-scaling, provisioned throughput, concurrency limits

**What DevOps Agent Should Discover:**
- DynamoDB tables use provisioned mode with no auto-scaling
- Inventory table has only 3 WCU/RCU (will throttle under load)
- ASG is fixed size (Min=Max=Desired=2), no scaling policies
- Lambda has no reserved concurrency (vulnerable to noisy neighbor)
- No capacity alarms to detect approaching limits

**Steps:**

```bash
# 1. Navigate to the lab
cd labs/lab2-capacity-planning/

# 2. Generate burst traffic to stress capacity
./inject.sh devops-eval

# 3. Check for DynamoDB throttling (confirms the gap)
aws cloudwatch get-metric-statistics \
    --namespace AWS/DynamoDB \
    --metric-name WriteThrottleEvents \
    --dimensions Name=TableName,Value=devops-eval-inventory \
    --start-time $(date -u -d '10 minutes ago' +%Y-%m-%dT%H:%M:%S) \
    --end-time $(date -u +%Y-%m-%dT%H:%M:%S) \
    --period 60 --statistics Sum

# 4. Verify ASG has no scaling policy
aws autoscaling describe-policies \
    --auto-scaling-group-name devops-eval-asg \
    --query 'ScalingPolicies' \
    --output text
# Expected: empty (no policies)

# 5. Trigger Evaluation focused on capacity
# "Evaluate capacity planning for devops-eval infrastructure.
#  Check DynamoDB throughput, ASG scaling, and Lambda concurrency."

# 6. Expected recommendations:
#   - Enable DynamoDB auto-scaling or switch to on-demand
#   - Add target tracking scaling policy to ASG
#   - Set Lambda reserved concurrency
#   - Add capacity utilization alarms

./rollback.sh devops-eval
```

---

### Lab 3: Resilience Weaknesses (Intermediate)

**Focus:** Retry logic, DLQ, error handling, code quality

**What DevOps Agent Should Discover:**
- Lambda functions have no Dead Letter Queue (failed events are lost)
- No retry logic in application code (single attempt, fail permanently)
- `inventory-checker` uses full table SCAN instead of GetItem/Query
- No input validation on order-processor (crashes on malformed input)
- `session-cleanup` is redundant (DynamoDB TTL already handles expiration)
- No pagination handling (will fail on large datasets)

**Steps:**

```bash
# 1. Navigate to the lab
cd labs/lab3-resilience-weaknesses/

# 2. Send malformed requests to expose missing validation
./inject.sh devops-eval

# 3. Check Lambda error logs
aws logs filter-log-events \
    --log-group-name /aws/lambda/devops-eval-order-processor \
    --filter-pattern "ERROR" \
    --start-time $(date -u -d '5 minutes ago' +%s)000 \
    --query 'events[*].message' \
    --output text | head -20

# 4. Verify no DLQ configured
aws lambda get-function-configuration \
    --function-name devops-eval-order-processor \
    --query 'DeadLetterConfig' \
    --output text
# Expected: None

# 5. Trigger Evaluation focused on resilience
# "Evaluate application resilience for devops-eval Lambda functions.
#  Check error handling, retry logic, DLQ configuration, and code patterns."

# 6. Expected recommendations:
#   - Add DLQ to all Lambda functions
#   - Add input validation to order-processor
#   - Replace table scan with GetItem in inventory-checker
#   - Add pagination handling
#   - Remove redundant session-cleanup function
#   - Add retry logic with exponential backoff

./rollback.sh devops-eval
```

---

### Lab 4: Deployment Safety (Advanced)

**Focus:** Rollback, canary deploy, versioning, validation

**What DevOps Agent Should Discover:**
- Lambda functions have no versioning or aliases (can't rollback)
- No canary/linear deployment strategy
- No CodeDeploy for EC2 instances (manual deployment only)
- No pre-deployment testing or smoke tests
- No rollback mechanism if a deploy fails
- EC2 app deployed via UserData only (no CI/CD pipeline)

**Steps:**

```bash
# 1. Navigate to the lab
cd labs/lab4-deployment-safety/

# 2. Deploy broken code to prove no rollback exists
./inject.sh devops-eval

# 3. Verify the function is broken (no way to auto-rollback)
API_ENDPOINT=$(aws cloudformation describe-stacks \
    --stack-name devops-eval \
    --query 'Stacks[0].Outputs[?OutputKey==`ApiEndpoint`].OutputValue' \
    --output text)

curl -s -X POST "${API_ENDPOINT}/orders" \
    -H "Content-Type: application/json" \
    -d '{"customerId":"test","items":[{"productId":"PROD-001","quantity":1}],"totalAmount":79}'
# Expected: error response

# 4. Check no Lambda versions exist
aws lambda list-versions-by-function \
    --function-name devops-eval-order-processor \
    --query 'Versions[*].Version' \
    --output text
# Expected: only $LATEST

# 5. Trigger Evaluation focused on deployment safety
# "Evaluate deployment safety for devops-eval resources.
#  Check versioning, rollback capabilities, and deployment strategies."

# 6. Expected recommendations:
#   - Enable Lambda versioning with aliases (prod, canary)
#   - Add CodeDeploy with canary/linear deployment
#   - Implement pre-deployment smoke tests
#   - Add rollback triggers on error metrics
#   - Use infrastructure-as-code for EC2 app deployments

# 7. Manual rollback (proves the gap - this should be automated)
./rollback.sh devops-eval
```

---

### Lab 5: Security Posture (Advanced)

**Focus:** API auth, IAM, encryption, WAF

**What DevOps Agent Should Discover:**
- API Gateway has `AuthorizationType: NONE` (unauthenticated access)
- No WAF attached to API Gateway or ALB
- Lambda IAM role has broad permissions (Scan + DeleteItem on all tables)
- SNS topics have no encryption (KMS)
- No VPC endpoints (data traverses public internet)
- No API throttling or usage plans
- No request validation models on API Gateway

**Steps:**

```bash
# 1. Navigate to the lab
cd labs/lab5-security-posture/

# 2. Demonstrate unauthenticated API access
./inject.sh devops-eval

# 3. Verify no auth on API
API_ENDPOINT=$(aws cloudformation describe-stacks \
    --stack-name devops-eval \
    --query 'Stacks[0].Outputs[?OutputKey==`ApiEndpoint`].OutputValue' \
    --output text)

# Anyone can call this without credentials:
curl -s "${API_ENDPOINT}/inventory"
# Expected: returns data with no authentication required

# 4. Check Lambda IAM role has overly broad permissions
ROLE_NAME="devops-eval-lambda-role"
aws iam get-role-policy \
    --role-name "${ROLE_NAME}" \
    --policy-name "DynamoDBAccess" \
    --query 'PolicyDocument.Statement[0].Action' \
    --output text
# Expected: includes dynamodb:Scan and dynamodb:DeleteItem (too broad)

# 5. Verify no WAF
aws wafv2 list-web-acls --scope REGIONAL \
    --query 'WebACLs[?contains(Name, `devops-eval`)]' \
    --output text
# Expected: empty

# 6. Trigger Evaluation focused on security
# "Evaluate security posture for devops-eval resources.
#  Check API authentication, IAM permissions, encryption, and WAF."

# 7. Expected recommendations:
#   - Add Cognito or IAM authorization to API Gateway
#   - Attach WAF with rate limiting rules
#   - Restrict Lambda IAM to least privilege (remove Scan, DeleteItem)
#   - Enable SSE-KMS on SNS topics
#   - Add API Gateway usage plan with throttling
#   - Add request validation models
#   - Consider VPC endpoints for DynamoDB

./rollback.sh devops-eval
```

---

## Intentional Gaps Summary

| Category | # of Gaps | Key Issues |
|----------|-----------|-----------|
| **Observability** | 8+ | Missing alarms for throttle, duration, latency, CPU; lenient thresholds; no X-Ray |
| **Capacity** | 4 | No DDB auto-scaling; fixed ASG; no reserved concurrency; no scaling policy |
| **Resilience** | 6 | No retry; no DLQ; table scans; no validation; no pagination; redundant function |
| **Deployment** | 5 | No versioning; no canary; no CodeDeploy; no rollback; no pre-deploy test |
| **Security** | 8+ | No auth; no WAF; broad IAM; no encryption; no throttling; no VPC endpoints |
| **Total** | **31+** | All discoverable by DevOps Agent Evaluations |

---

## Cost Estimate

| Service | Cost Driver | Estimate |
|---------|------------|----------|
| EC2 | 2x t3.micro (on-demand) | ~$1.04/hr |
| ALB | Load balancer hour + LCU | ~$0.50/hr |
| DynamoDB | 3 tables (provisioned, low throughput) | ~$0.15/hr |
| Lambda | Invocations (minimal outside labs) | ~$0.01/hr |
| CloudWatch | 3 alarms + log storage | ~$0.05/hr |
| **Total** | | **~$2/hr** |

**Important:** Run `cleanup.sh` when done to stop charges.

---

## Cleanup

```bash
./scripts/cleanup.sh devops-eval
```

The script will:
1. Prompt for confirmation
2. Delete the CloudFormation stack
3. Wait for deletion to complete

### Verify Cleanup

```bash
aws cloudformation describe-stacks --stack-name devops-eval 2>&1 | \
    grep -q "does not exist" && echo "Clean" || echo "Stack still exists"
```

---

## Troubleshooting

| Problem | Solution |
|---------|----------|
| Evaluation not running | Verify Agent Space has Evaluations enabled (separate from Investigations) |
| No recommendations generated | Ensure resource tags match Agent Space discovery filter (`devopsagent=true`) |
| Lambda errors on deploy | Wait 30s for function to become Active; check IAM role creation |
| API Gateway returns 403 | Check API stage is deployed; may need stack update |
| ALB unhealthy after deploy | Wait 2-3 min for instance boot + gunicorn start on port 8080 |
| Stack fails with IAM error | Ensure deploying user has `iam:CreateRole` and `iam:CreateInstanceProfile` |
| Evaluation finds nothing | Generate traffic first (Lab 1 inject.sh) to populate metrics; wait 5 min |
| EC2 instances not joining TG | Check security group allows port 8080 from ALB SG; verify UserData ran |

### Checking EC2 Instance Health

```bash
# Via SSM Session Manager
aws ssm start-session --target <instance-id>

# Check if gunicorn is running on port 8080
sudo systemctl status webapp
curl http://localhost:8080/health
```

### Checking API Gateway

```bash
API_ENDPOINT=$(aws cloudformation describe-stacks \
    --stack-name devops-eval \
    --query 'Stacks[0].Outputs[?OutputKey==`ApiEndpoint`].OutputValue' \
    --output text)

# Test inventory endpoint
curl -s "${API_ENDPOINT}/inventory" | python3 -m json.tool

# Test order endpoint
curl -s -X POST "${API_ENDPOINT}/orders" \
    -H "Content-Type: application/json" \
    -d '{"customerId":"TEST","items":[{"productId":"PROD-001","quantity":1}],"totalAmount":79}'
```
