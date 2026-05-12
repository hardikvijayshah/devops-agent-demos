# Serverless Workshop - Deployment Guide

A standalone, hands-on workshop demonstrating AWS DevOps Agent's autonomous investigation capabilities across a serverless order processing application. Five labs inject realistic failures into Lambda, Step Functions, DynamoDB, API Gateway, and EventBridge — then showcase how DevOps Agent correlates telemetry across services to identify root causes.

---

## Overview

This demo deploys a complete serverless order processing system:

| Component | What's Deployed | Count |
|-----------|----------------|-------|
| API Gateway | REST API (POST /orders, GET /orders) with X-Ray tracing | 1 API, 2 methods |
| Lambda | order-api, validate-order, process-payment, update-inventory, send-notification, seed-data | 6 functions |
| Step Functions | Order workflow state machine (validate → pay → inventory → notify) | 1 state machine |
| DynamoDB | Orders, Inventory, Payments tables (provisioned 5 RCU/5 WCU) | 3 tables |
| EventBridge | Custom bus, OrderCompleted rule, OrderFailed rule | 1 bus, 2 rules |
| SQS | Dead Letter Queue (14-day retention) | 1 queue |
| SNS | Notification topic, Alarm topic | 2 topics |
| CloudWatch | Lambda errors, duration, SFN failures, DDB throttle, API 5xx, latency, DLQ, validate errors | 8 alarms |
| IAM | Lambda role, Step Functions role, API Gateway log role | 3 roles |

**Total CloudFormation Resources:** 43  
**Deploy Time:** ~5-8 minutes  
**Estimated Cost:** ~$1-2/hour  
**Discovery Tag:** `devopsagent = true`

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
iam:GetRole, iam:DeleteRole, iam:DeleteRolePolicy, iam:DetachRolePolicy

lambda:CreateFunction, lambda:UpdateFunctionConfiguration, lambda:UpdateFunctionCode,
lambda:GetFunction, lambda:GetFunctionConfiguration, lambda:DeleteFunction,
lambda:InvokeFunction, lambda:AddPermission, lambda:RemovePermission

apigateway:* (REST API CRUD, deployment, stage management)
states:* (Step Functions state machine CRUD, execution management)
dynamodb:* (table CRUD, item operations)
sqs:* (queue CRUD)
sns:* (topic CRUD, subscriptions)
events:* (EventBridge bus, rules CRUD)
cloudwatch:* (alarms, metrics)
cloudformation:* (stack CRUD)
logs:* (log groups)
```

### DevOps Agent Space Setup

1. Navigate to the [AWS DevOps Agent console](https://console.aws.amazon.com/devops-agent/)
2. Create or select an Agent Space
3. Add the target AWS account as a monitored account
4. Configure tag-based resource discovery: `devopsagent = true`
5. Ensure access to CloudWatch Logs, Metrics, and CloudTrail
6. (Optional) Configure alarm webhook for automatic investigation triggers

### Recommended

- **Region:** `us-east-1` (default, all services available)
- **CloudTrail:** Enabled for Lambda config changes, DynamoDB throughput changes, EventBridge rule updates

---

## Folder Structure

```
serverless-workshop/
├── DEPLOYMENT_GUIDE.md              ← This file
├── README.md                         ← Architecture details and lab descriptions
├── cloudformation/
│   └── serverless-workshop.yaml      ← 43 resources (complete infrastructure)
├── labs/
│   ├── lab1-lambda-timeout/
│   │   ├── inject.sh                 ← Reduces timeout to 1s, memory to 128MB
│   │   ├── rollback.sh              ← Restores timeout to 30s, memory to 256MB
│   │   └── README.md
│   ├── lab2-stepfunctions-failure/
│   │   ├── inject.sh                 ← Deploys broken Lambda code (KeyError)
│   │   ├── rollback.sh              ← Restores original validation code
│   │   └── README.md
│   ├── lab3-dynamodb-throttle/
│   │   ├── inject.sh                 ← Reduces DynamoDB to 1 RCU/WCU
│   │   ├── rollback.sh              ← Restores to 5 RCU/WCU
│   │   └── README.md
│   ├── lab4-api-gateway-errors/
│   │   ├── inject.sh                 ← Deploys Lambda returning malformed responses
│   │   ├── rollback.sh              ← Restores original order-api code
│   │   └── README.md
│   └── lab5-eventbridge-misconfig/
│       ├── inject.sh                 ← Changes rule pattern to non-matching
│       ├── rollback.sh              ← Restores correct event pattern
│       └── README.md
├── scripts/
│   ├── deploy.sh                     ← CloudFormation deploy with validation
│   ├── cleanup.sh                    ← Stack deletion with confirmation
│   └── generate-traffic.sh           ← Sends randomized order requests via curl
└── tests/
    └── validate-stack.sh             ← Verifies all resources, seed data, connectivity
```

---

## Step-by-Step Deployment

### Step 1: Navigate to the Workshop Directory

```bash
cd serverless-workshop
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
# Default deployment (stack: devops-agent-serverless, region: us-east-1)
./scripts/deploy.sh

# OR with custom stack name and alarm email notifications
./scripts/deploy.sh my-serverless-demo user@example.com

# OR in a specific region
export AWS_REGION=us-west-2
./scripts/deploy.sh
```

The deploy script will:
1. Validate the CloudFormation template syntax
2. Deploy the stack with `CAPABILITY_NAMED_IAM`
3. Tag all resources with `devopsagent=true`
4. Print all stack outputs (API endpoint, table names, ARNs)
5. Seed data Lambda automatically populates Inventory table with 5 products

**Expected duration:** 5-8 minutes

### Step 5: Validate the Deployment

```bash
./tests/validate-stack.sh devops-agent-serverless
```

This checks:
- Stack status (CREATE_COMPLETE or UPDATE_COMPLETE)
- All 5 Lambda functions are Active
- All 3 DynamoDB tables are ACTIVE
- Step Functions state machine is ACTIVE
- API Gateway endpoint is reachable
- EventBridge custom bus exists
- SQS Dead Letter Queue exists
- 8 CloudWatch alarms exist
- Inventory table has 5 seed products
- End-to-end test: submits a test order and verifies HTTP 200

### Step 6: Note the API Endpoint

```bash
aws cloudformation describe-stacks \
    --stack-name devops-agent-serverless \
    --query 'Stacks[0].Outputs[?OutputKey==`ApiEndpoint`].OutputValue' \
    --output text
```

Save this URL — you'll use it for traffic generation and testing.

---

## Executing the Labs

Each lab follows the same pattern: **inject → generate traffic → wait for alarms → investigate → rollback**

### Lab 1: Lambda Timeout (Beginner)

**What Gets Broken:** order-api Lambda timeout reduced from 30s to 1s, memory from 256MB to 128MB  
**Impact:** API returns 502/504 errors, no orders processed  
**Alarms Triggered:** `order-api-errors`, `order-api-duration`, `api-5xx-errors`

**Steps:**

```bash
# 1. Navigate to the lab
cd labs/lab1-lambda-timeout/

# 2. Inject the failure
./inject.sh devops-agent-serverless

# 3. Generate traffic (30 requests, 1 second apart)
../../scripts/generate-traffic.sh devops-agent-serverless 30 1
# Most requests will show FAILED status

# 4. Wait 2-3 minutes, then check alarms
aws cloudwatch describe-alarms \
    --alarm-name-prefix devops-agent-serverless \
    --state-value ALARM \
    --query 'MetricAlarms[*].[AlarmName,StateValue]' \
    --output table

# 5. Investigate with DevOps Agent
# Ask: "Investigate why the order API is failing"
# OR: "Why are there 5xx errors on the order processing API?"

# 6. Expected findings:
#   - Root cause: Lambda timeout set to 1s (insufficient for DDB write + SFN start)
#   - Evidence: "Task timed out after 1.00 seconds" in CloudWatch Logs
#   - Correlation: Config change timestamp matches error spike
#   - Recommendation: Increase timeout to 30s and memory to 256MB

# 7. Rollback
./rollback.sh devops-agent-serverless
```

---

### Lab 2: Step Functions Failure (Intermediate)

**What Gets Broken:** validate-order Lambda code replaced with broken version that accesses `order['orderDetails']['itemList']['entries']` (non-existent path)  
**Impact:** Orders accepted by API but workflow fails at validation step  
**Alarms Triggered:** `sfn-failures`, `validate-order-errors`, `dlq-messages`

**Steps:**

```bash
# 1. Navigate to the lab
cd labs/lab2-stepfunctions-failure/

# 2. Inject the failure
./inject.sh devops-agent-serverless

# 3. Generate traffic
../../scripts/generate-traffic.sh devops-agent-serverless 20 2
# Orders will be accepted (HTTP 200) but workflows will fail

# 4. Wait 2-3 minutes, then check alarms
aws cloudwatch describe-alarms \
    --alarm-name-prefix devops-agent-serverless \
    --state-value ALARM \
    --query 'MetricAlarms[*].[AlarmName,StateValue]' \
    --output table

# 5. Check Step Functions failures directly
aws stepfunctions list-executions \
    --state-machine-arn $(aws cloudformation describe-stacks \
        --stack-name devops-agent-serverless \
        --query 'Stacks[0].Outputs[?OutputKey==`StateMachineArn`].OutputValue' \
        --output text) \
    --status-filter FAILED \
    --query 'executions[0:5].[name,status,stopDate]' \
    --output table

# 6. Investigate with DevOps Agent
# Ask: "Why are Step Functions workflows failing?"
# OR: "Orders are being accepted but not processed. Investigate."

# 7. Expected findings:
#   - Executions failing at ValidateOrder state
#   - KeyError in validate-order Lambda logs
#   - Code change detected as root cause
#   - Recommendation: Fix data access path in validation code

# 8. Rollback
./rollback.sh devops-agent-serverless
```

---

### Lab 3: DynamoDB Throttle (Intermediate)

**What Gets Broken:** Inventory table provisioned throughput reduced to 1 RCU / 1 WCU  
**Impact:** Cascading failure: DDB throttle → Lambda fail → SFN fail → DLQ  
**Alarms Triggered:** `dynamodb-throttle`, `sfn-failures`, `dlq-messages`

**Steps:**

```bash
# 1. Navigate to the lab
cd labs/lab3-dynamodb-throttle/

# 2. Inject the failure
./inject.sh devops-agent-serverless

# 3. Generate HEAVY traffic (50 requests, 0.5s apart)
../../scripts/generate-traffic.sh devops-agent-serverless 50 0.5

# 4. Wait 2-3 minutes, then check alarms
aws cloudwatch describe-alarms \
    --alarm-name-prefix devops-agent-serverless \
    --state-value ALARM \
    --query 'MetricAlarms[*].[AlarmName,StateValue]' \
    --output table

# 5. Verify throttling in metrics
aws cloudwatch get-metric-statistics \
    --namespace AWS/DynamoDB \
    --metric-name WriteThrottleEvents \
    --dimensions Name=TableName,Value=devops-agent-serverless-inventory \
    --start-time $(date -u -d '10 minutes ago' +%Y-%m-%dT%H:%M:%S) \
    --end-time $(date -u +%Y-%m-%dT%H:%M:%S) \
    --period 60 --statistics Sum

# 6. Investigate with DevOps Agent
# Ask: "Orders are failing with throttling errors. What's happening?"
# OR: "Investigate DynamoDB throttling on the inventory table"

# 7. Expected findings:
#   - DynamoDB WriteThrottleEvents spike on inventory table
#   - Cascading: throttle → ProvisionedThroughputExceededException → Lambda error → SFN failure
#   - Throughput change detected (5 → 1 WCU)
#   - Recommendation: Increase throughput or switch to on-demand billing

# 8. Rollback
./rollback.sh devops-agent-serverless
```

---

### Lab 4: API Gateway 5xx Errors (Intermediate)

**What Gets Broken:** order-api Lambda code replaced with version returning malformed responses (missing statusCode, unhandled exceptions, non-string body)  
**Impact:** All API requests return 502 Bad Gateway  
**Alarms Triggered:** `api-5xx-errors`, `order-api-errors`

**Steps:**

```bash
# 1. Navigate to the lab
cd labs/lab4-api-gateway-errors/

# 2. Inject the failure
./inject.sh devops-agent-serverless

# 3. Generate traffic
../../scripts/generate-traffic.sh devops-agent-serverless 30 1
# All requests will show FAILED (502)

# 4. Wait 2-3 minutes, then check alarms
aws cloudwatch describe-alarms \
    --alarm-name-prefix devops-agent-serverless \
    --state-value ALARM \
    --query 'MetricAlarms[*].[AlarmName,StateValue]' \
    --output table

# 5. Investigate with DevOps Agent
# Ask: "API Gateway is returning 502 errors on all requests. Why?"
# OR: "Investigate the order API 5xx error spike"

# 6. Expected findings:
#   - API Gateway returning 502 due to malformed Lambda proxy response
#   - Lambda integration errors (missing statusCode, non-string body)
#   - Code change detected as root cause
#   - Recommendation: Fix Lambda response format (needs statusCode, string body)

# 7. Rollback
./rollback.sh devops-agent-serverless
```

---

### Lab 5: EventBridge Misconfiguration (Advanced)

**What Gets Broken:** EventBridge rule pattern changed from `order.service`/`OrderCompleted` to `order.service.v2`/`OrderCompletedV2`  
**Impact:** Orders complete successfully but notifications silently stop (no errors!)  
**Alarms Triggered:** None initially — this is a **silent failure**

**Steps:**

```bash
# 1. Navigate to the lab
cd labs/lab5-eventbridge-misconfig/

# 2. Inject the failure
./inject.sh devops-agent-serverless

# 3. Generate traffic (orders will succeed)
../../scripts/generate-traffic.sh devops-agent-serverless 15 2
# All requests show OK — no apparent failure!

# 4. Verify orders succeed but notifications don't arrive
# Check SNS - no messages published:
aws cloudwatch get-metric-statistics \
    --namespace AWS/SNS \
    --metric-name NumberOfMessagesPublished \
    --dimensions Name=TopicName,Value=devops-agent-serverless-notifications \
    --start-time $(date -u -d '10 minutes ago' +%Y-%m-%dT%H:%M:%S) \
    --end-time $(date -u +%Y-%m-%dT%H:%M:%S) \
    --period 300 --statistics Sum
# Expected: 0 messages (should be > 0)

# 5. Investigate with DevOps Agent
# Ask: "Order notifications have stopped. Orders complete but no SNS messages arrive."
# OR: "Investigate why the notification system stopped working"

# 6. Expected findings:
#   - EventBridge rule pattern doesn't match published events
#   - Rule expects "order.service.v2" but events use "order.service"
#   - SNS delivery dropped to zero correlated with rule change
#   - Configuration change detected via CloudTrail

# 7. Rollback
./rollback.sh devops-agent-serverless
```

---

## Generating Traffic

The `generate-traffic.sh` script sends realistic order requests:

```bash
# Usage: ./scripts/generate-traffic.sh [stack-name] [count] [interval-seconds]

# Default: 20 requests, 2s apart
./scripts/generate-traffic.sh devops-agent-serverless

# Heavy load: 50 requests, 0.5s apart
./scripts/generate-traffic.sh devops-agent-serverless 50 0.5

# Quick test: 5 requests, 1s apart
./scripts/generate-traffic.sh devops-agent-serverless 5 1
```

Each request sends a randomized order with:
- Random customer (CUST-001 through CUST-005)
- Random product (PROD-001 through PROD-005)
- Random quantity (1-3)
- Random amount ($10-$210)

---

## Cost Estimate

| Service | Cost Driver | Estimate |
|---------|------------|----------|
| DynamoDB | 3 tables × 5 RCU/WCU provisioned | ~$0.50/hr |
| Lambda | Invocations during traffic generation | ~$0.01/hr |
| API Gateway | REST API requests | ~$0.01/hr |
| Step Functions | State transitions | ~$0.01/hr |
| CloudWatch | 8 alarms + log storage | ~$0.10/hr |
| SQS/SNS | Messages (minimal) | ~$0.01/hr |
| **Total** | | **~$1-2/hr** |

**Important:** Run `cleanup.sh` when done to stop charges. DynamoDB provisioned capacity is billed continuously.

---

## Cleanup

```bash
./scripts/cleanup.sh devops-agent-serverless
```

The script will:
1. Prompt for confirmation (y/N)
2. Delete the entire CloudFormation stack
3. Wait for stack deletion to complete

### Verify Cleanup

```bash
aws cloudformation describe-stacks --stack-name devops-agent-serverless 2>&1 | \
    grep -q "does not exist" && echo "Clean" || echo "Stack still exists"
```

---

## Troubleshooting

| Problem | Solution |
|---------|----------|
| Stack fails with IAM error | Ensure deploying user has `iam:CreateRole` and `iam:PutRolePolicy` permissions |
| Lambda functions not in Agent Space | Verify `devopsagent=true` tag; check Agent Space tag filter matches |
| Alarms not triggering | Generate more traffic (`50 0.5`); wait 2+ evaluation periods (each is 60s) |
| API returns 403 Forbidden | API Gateway stage may not be deployed; run stack update |
| Seed data missing (0 inventory items) | Check SeedDataFunction CloudWatch Logs; re-deploy stack |
| Rollback doesn't clear alarms | Alarms need 1-2 evaluation periods of healthy metrics to return to OK |
| `generate-traffic.sh` shows all FAILED | Confirm API endpoint is correct; try `curl` manually to the endpoint |
| Stack deletion fails | Check for Lambda@Edge replicas or custom resources; wait and retry |

### Manual API Test

```bash
API_ENDPOINT=$(aws cloudformation describe-stacks \
    --stack-name devops-agent-serverless \
    --query 'Stacks[0].Outputs[?OutputKey==`ApiEndpoint`].OutputValue' \
    --output text)

# Submit a test order
curl -s -X POST "${API_ENDPOINT}" \
    -H "Content-Type: application/json" \
    -d '{"customerId":"TEST-001","items":[{"productId":"PROD-001","quantity":1,"price":79}],"totalAmount":79}' | \
    python3 -m json.tool
```

### Checking CloudWatch Logs

```bash
# Order API logs
aws logs tail /aws/lambda/devops-agent-serverless-order-api --since 5m

# Validate Order logs
aws logs tail /aws/lambda/devops-agent-serverless-validate-order --since 5m
```
