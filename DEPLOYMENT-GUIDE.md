# AWS DevOps Agent Demos - Deployment Guide

Step-by-step guide to deploy both workshops to your AWS account. Covers local setup, AWS CloudShell, and post-deployment validation.

---

## Table of Contents

1. [Prerequisites Setup](#1-prerequisites-setup)
2. [Deploy Workshop 1: Serverless](#2-deploy-workshop-1-serverless-application)
3. [Deploy Workshop 2: CI/CD Pipeline](#3-deploy-workshop-2-cicd-pipeline)
4. [Post-Deployment Validation](#4-post-deployment-validation)
5. [Configure DevOps Agent Space](#5-configure-devops-agent-space)
6. [Run Your First Lab](#6-run-your-first-lab)
7. [Cost Management](#7-cost-management)
8. [Cleanup](#8-cleanup)
9. [Troubleshooting](#9-troubleshooting)

---

## 1. Prerequisites Setup

### 1.1 AWS Account Requirements

| Requirement | Details |
|-------------|---------|
| AWS Account | Active account with billing enabled |
| Region | `us-east-1` recommended (all services + DevOps Agent GA) |
| IAM Permissions | See minimum permissions below |
| Service Quotas | Default quotas are sufficient |

### 1.2 Minimum IAM Permissions

The deploying user/role needs the following permissions. If you have `AdministratorAccess`, skip this section.

```json
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Effect": "Allow",
            "Action": [
                "cloudformation:*",
                "iam:CreateRole",
                "iam:DeleteRole",
                "iam:PutRolePolicy",
                "iam:DeleteRolePolicy",
                "iam:GetRole",
                "iam:GetRolePolicy",
                "iam:PassRole",
                "iam:CreateInstanceProfile",
                "iam:DeleteInstanceProfile",
                "iam:AddRoleToInstanceProfile",
                "iam:RemoveRoleFromInstanceProfile",
                "lambda:*",
                "apigateway:*",
                "states:*",
                "dynamodb:*",
                "sqs:*",
                "sns:*",
                "events:*",
                "logs:*",
                "cloudwatch:*",
                "ec2:*",
                "elasticloadbalancing:*",
                "autoscaling:*",
                "codepipeline:*",
                "codebuild:*",
                "codedeploy:*",
                "codestar-notifications:*",
                "s3:*",
                "ssm:GetParameter"
            ],
            "Resource": "*"
        }
    ]
}
```

### 1.3 Install Tools

#### Option A: Local Machine (Windows/WSL/Mac/Linux)

```bash
# Install AWS CLI v2
# Windows: Download from https://awscli.amazonaws.com/AWSCLIV2.msi
# Mac:     brew install awscli
# Linux:   curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "awscliv2.zip" && unzip awscliv2.zip && sudo ./aws/install

# Verify installation
aws --version

# Configure credentials
aws configure
# Enter: AWS Access Key ID, Secret Access Key, Region (us-east-1), Output (json)

# Verify credentials
aws sts get-caller-identity
```

#### Option B: AWS CloudShell (No Local Setup)

1. Open [AWS CloudShell](https://console.aws.amazon.com/cloudshell/) in your browser
2. AWS CLI is pre-installed and pre-authenticated
3. Upload the workshop files (see section 1.4)

### 1.4 Get Workshop Files Into Your Environment

#### Option A: Clone or Copy Locally

```bash
# If using git
git clone <your-repo-url> devops-agent-demos
cd devops-agent-demos

# If copying manually, ensure this structure exists:
# devops-agent-demos/
#   serverless-workshop/cloudformation/serverless-workshop.yaml
#   serverless-workshop/scripts/*.sh
#   serverless-workshop/labs/*/inject.sh
#   serverless-workshop/labs/*/rollback.sh
#   cicd-pipeline-workshop/cloudformation/cicd-workshop.yaml
#   cicd-pipeline-workshop/scripts/*.sh
#   cicd-pipeline-workshop/labs/*/inject.sh
#   cicd-pipeline-workshop/labs/*/rollback.sh
```

#### Option B: Upload to AWS CloudShell

1. In CloudShell, click **Actions** > **Upload file**
2. Upload each CloudFormation template:
   - `serverless-workshop/cloudformation/serverless-workshop.yaml`
   - `cicd-pipeline-workshop/cloudformation/cicd-workshop.yaml`
3. Or zip the entire project and upload + unzip:
   ```bash
   # On your local machine first:
   cd devops-agent-demos
   zip -r devops-agent-demos.zip .

   # After uploading to CloudShell:
   mkdir -p ~/devops-agent-demos && cd ~/devops-agent-demos
   unzip ~/devops-agent-demos.zip
   ```

### 1.5 Make Scripts Executable

```bash
cd devops-agent-demos
chmod +x serverless-workshop/scripts/*.sh
chmod +x serverless-workshop/labs/*/inject.sh
chmod +x serverless-workshop/labs/*/rollback.sh
chmod +x serverless-workshop/tests/*.sh
chmod +x cicd-pipeline-workshop/scripts/*.sh
chmod +x cicd-pipeline-workshop/labs/*/inject.sh
chmod +x cicd-pipeline-workshop/labs/*/rollback.sh
chmod +x cicd-pipeline-workshop/tests/*.sh
```

---

## 2. Deploy Workshop 1: Serverless Application

**Time required:** ~5-8 minutes
**Cost:** ~$1-2/hour while running

### 2.1 Set Environment Variables

```bash
export AWS_REGION=us-east-1
export SERVERLESS_STACK_NAME=devops-agent-serverless

# Optional: set alarm notification email
export ALARM_EMAIL=your-email@example.com
```

### 2.2 Validate the Template

```bash
aws cloudformation validate-template \
    --template-body file://serverless-workshop/cloudformation/serverless-workshop.yaml \
    --region ${AWS_REGION}
```

Expected output: JSON with parameters list. If you see an error, check YAML syntax.

### 2.3 Deploy the Stack

#### Using the deploy script:

```bash
cd serverless-workshop
./scripts/deploy.sh ${SERVERLESS_STACK_NAME} ${ALARM_EMAIL}
```

#### Or manually with AWS CLI:

```bash
aws cloudformation deploy \
    --template-file serverless-workshop/cloudformation/serverless-workshop.yaml \
    --stack-name ${SERVERLESS_STACK_NAME} \
    --parameter-overrides \
        ResourcePrefix=${SERVERLESS_STACK_NAME} \
        AlarmEmail=${ALARM_EMAIL:-""} \
    --capabilities CAPABILITY_NAMED_IAM \
    --region ${AWS_REGION} \
    --tags devopsagent=true Workshop=serverless-troubleshooting
```

### 2.4 Monitor Deployment

```bash
# Watch stack events in real-time
aws cloudformation describe-stack-events \
    --stack-name ${SERVERLESS_STACK_NAME} \
    --region ${AWS_REGION} \
    --query 'StackEvents[0:10].[Timestamp,ResourceType,LogicalResourceId,ResourceStatus]' \
    --output table

# Or wait for completion
aws cloudformation wait stack-create-complete \
    --stack-name ${SERVERLESS_STACK_NAME} \
    --region ${AWS_REGION}
echo "Stack deployment complete!"
```

### 2.5 Retrieve Stack Outputs

```bash
aws cloudformation describe-stacks \
    --stack-name ${SERVERLESS_STACK_NAME} \
    --region ${AWS_REGION} \
    --query 'Stacks[0].Outputs[*].[OutputKey,OutputValue]' \
    --output table
```

Save these values -- you will need them:

| Output Key | Used For |
|-----------|----------|
| `ApiEndpoint` | Sending test orders (traffic generation) |
| `StateMachineArn` | Checking Step Functions executions |
| `OrderApiFunctionName` | Lab 1 and Lab 4 inject/rollback |
| `ValidateOrderFunctionName` | Lab 2 inject/rollback |
| `InventoryTableName` | Lab 3 inject/rollback |
| `EventBusName` | Lab 5 inject/rollback |

### 2.6 Quick Smoke Test

```bash
# Get API endpoint
API_ENDPOINT=$(aws cloudformation describe-stacks \
    --stack-name ${SERVERLESS_STACK_NAME} \
    --region ${AWS_REGION} \
    --query 'Stacks[0].Outputs[?OutputKey==`ApiEndpoint`].OutputValue' \
    --output text)

echo "API Endpoint: ${API_ENDPOINT}"

# Submit a test order
curl -s -X POST ${API_ENDPOINT} \
    -H "Content-Type: application/json" \
    -d '{
        "customerId": "TEST-001",
        "items": [{"productId": "PROD-001", "quantity": 1, "price": 79}],
        "totalAmount": 79
    }' | python3 -m json.tool 2>/dev/null || cat
```

Expected response:
```json
{
    "message": "Order received",
    "orderId": "xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx",
    "status": "RECEIVED"
}
```

### 2.7 Verify Step Functions Execution

```bash
SFN_ARN=$(aws cloudformation describe-stacks \
    --stack-name ${SERVERLESS_STACK_NAME} \
    --region ${AWS_REGION} \
    --query 'Stacks[0].Outputs[?OutputKey==`StateMachineArn`].OutputValue' \
    --output text)

aws stepfunctions list-executions \
    --state-machine-arn ${SFN_ARN} \
    --max-results 5 \
    --query 'executions[*].[name,status,startDate]' \
    --output table
```

Expected: At least one execution with status `SUCCEEDED`.

### 2.8 Verify All Alarms Are OK

```bash
aws cloudwatch describe-alarms \
    --alarm-name-prefix ${SERVERLESS_STACK_NAME} \
    --region ${AWS_REGION} \
    --query 'MetricAlarms[*].[AlarmName,StateValue]' \
    --output table
```

Expected: All 8 alarms showing `OK` or `INSUFFICIENT_DATA` (not `ALARM`).

---

## 3. Deploy Workshop 2: CI/CD Pipeline

**Time required:** ~10-15 minutes
**Cost:** ~$2-3/hour while running

### 3.1 Set Environment Variables

```bash
export AWS_REGION=us-east-1
export CICD_STACK_NAME=devops-agent-cicd

# Optional: alarm notification email
export ALARM_EMAIL=your-email@example.com
```

### 3.2 Validate the Template

```bash
aws cloudformation validate-template \
    --template-body file://cicd-pipeline-workshop/cloudformation/cicd-workshop.yaml \
    --region ${AWS_REGION}
```

### 3.3 Deploy the Stack

#### Using the deploy script:

```bash
cd cicd-pipeline-workshop
./scripts/deploy.sh ${CICD_STACK_NAME} ${ALARM_EMAIL}
```

#### Or manually with AWS CLI:

```bash
aws cloudformation deploy \
    --template-file cicd-pipeline-workshop/cloudformation/cicd-workshop.yaml \
    --stack-name ${CICD_STACK_NAME} \
    --parameter-overrides \
        ResourcePrefix=${CICD_STACK_NAME} \
        AlarmEmail=${ALARM_EMAIL:-""} \
    --capabilities CAPABILITY_NAMED_IAM \
    --region ${AWS_REGION} \
    --tags devopsagent=true Workshop=cicd-pipeline
```

### 3.4 Monitor Deployment

```bash
# Watch stack events
aws cloudformation describe-stack-events \
    --stack-name ${CICD_STACK_NAME} \
    --region ${AWS_REGION} \
    --query 'StackEvents[0:10].[Timestamp,ResourceType,LogicalResourceId,ResourceStatus]' \
    --output table

# Wait for completion
aws cloudformation wait stack-create-complete \
    --stack-name ${CICD_STACK_NAME} \
    --region ${AWS_REGION}
echo "Stack deployment complete!"
```

### 3.5 Retrieve Stack Outputs

```bash
aws cloudformation describe-stacks \
    --stack-name ${CICD_STACK_NAME} \
    --region ${AWS_REGION} \
    --query 'Stacks[0].Outputs[*].[OutputKey,OutputValue]' \
    --output table
```

Key outputs:

| Output Key | Used For |
|-----------|----------|
| `ALBEndpoint` | Application health checks and traffic generation |
| `PipelineName` | Monitoring pipeline state |
| `PipelineConsoleUrl` | Direct link to CodePipeline console |
| `ArtifactBucketName` | Lab inject scripts (upload modified source) |
| `CodeBuildRoleArn` | Lab 5 (IAM permission changes) |

### 3.6 Wait for EC2 Instances to Become Healthy

EC2 instances need time to boot, install CodeDeploy agent, and pass ALB health checks.

```bash
ALB_ENDPOINT=$(aws cloudformation describe-stacks \
    --stack-name ${CICD_STACK_NAME} \
    --region ${AWS_REGION} \
    --query 'Stacks[0].Outputs[?OutputKey==`ALBEndpoint`].OutputValue' \
    --output text)

echo "ALB Endpoint: ${ALB_ENDPOINT}"

# Poll until healthy (may take 3-5 minutes)
for i in $(seq 1 30); do
    HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" ${ALB_ENDPOINT}/health --connect-timeout 5 --max-time 10 2>/dev/null || echo "000")
    if [ "${HTTP_CODE}" = "200" ]; then
        echo "Instances are healthy! (HTTP 200)"
        break
    fi
    echo "Waiting for instances... attempt ${i}/30 (HTTP ${HTTP_CODE})"
    sleep 20
done
```

### 3.7 Trigger Initial Pipeline Execution

```bash
PIPELINE_NAME=$(aws cloudformation describe-stacks \
    --stack-name ${CICD_STACK_NAME} \
    --region ${AWS_REGION} \
    --query 'Stacks[0].Outputs[?OutputKey==`PipelineName`].OutputValue' \
    --output text)

aws codepipeline start-pipeline-execution \
    --name ${PIPELINE_NAME} \
    --region ${AWS_REGION}

echo "Pipeline triggered: ${PIPELINE_NAME}"
echo "Console: $(aws cloudformation describe-stacks \
    --stack-name ${CICD_STACK_NAME} \
    --region ${AWS_REGION} \
    --query 'Stacks[0].Outputs[?OutputKey==`PipelineConsoleUrl`].OutputValue' \
    --output text)"
```

### 3.8 Monitor Pipeline Execution

```bash
# Check pipeline stage status
aws codepipeline get-pipeline-state \
    --name ${PIPELINE_NAME} \
    --region ${AWS_REGION} \
    --query 'stageStates[*].{Stage:stageName,Status:latestExecution.status}' \
    --output table
```

Wait until all 4 stages show `Succeeded` (~5-8 minutes).

### 3.9 Quick Smoke Test

```bash
# Test all endpoints
echo "--- Health ---"
curl -s ${ALB_ENDPOINT}/health | python3 -m json.tool 2>/dev/null || curl -s ${ALB_ENDPOINT}/health

echo ""
echo "--- Index ---"
curl -s ${ALB_ENDPOINT}/ | python3 -m json.tool 2>/dev/null || curl -s ${ALB_ENDPOINT}/

echo ""
echo "--- Status ---"
curl -s ${ALB_ENDPOINT}/api/status | python3 -m json.tool 2>/dev/null || curl -s ${ALB_ENDPOINT}/api/status

echo ""
echo "--- Process ---"
curl -s -X POST ${ALB_ENDPOINT}/api/process \
    -H "Content-Type: application/json" \
    -d '{"key":"value"}' | python3 -m json.tool 2>/dev/null || curl -s -X POST ${ALB_ENDPOINT}/api/process -H "Content-Type: application/json" -d '{"key":"value"}'
```

Expected: All 4 endpoints return HTTP 200 with JSON responses.

---

## 4. Post-Deployment Validation

### 4.1 Full Validation Scripts

```bash
# Validate serverless workshop
cd serverless-workshop
./tests/validate-stack.sh ${SERVERLESS_STACK_NAME}

# Validate CI/CD workshop
cd ../cicd-pipeline-workshop
./tests/validate-stack.sh ${CICD_STACK_NAME}
```

### 4.2 Manual Validation Checklist

#### Serverless Workshop

```bash
# [ ] Stack status is CREATE_COMPLETE
aws cloudformation describe-stacks --stack-name ${SERVERLESS_STACK_NAME} \
    --query 'Stacks[0].StackStatus' --output text

# [ ] All 6 Lambda functions exist
for fn in order-api validate-order process-payment update-inventory send-notification seed-data; do
    echo -n "${fn}: "
    aws lambda get-function --function-name ${SERVERLESS_STACK_NAME}-${fn} \
        --query 'Configuration.State' --output text 2>/dev/null || echo "MISSING"
done

# [ ] All 3 DynamoDB tables exist
for table in orders inventory payments; do
    echo -n "${table}: "
    aws dynamodb describe-table --table-name ${SERVERLESS_STACK_NAME}-${table} \
        --query 'Table.TableStatus' --output text 2>/dev/null || echo "MISSING"
done

# [ ] Inventory has 5 seed products
aws dynamodb scan --table-name ${SERVERLESS_STACK_NAME}-inventory \
    --select COUNT --query 'Count' --output text

# [ ] Step Functions state machine exists
aws stepfunctions describe-state-machine \
    --state-machine-arn $(aws cloudformation describe-stacks --stack-name ${SERVERLESS_STACK_NAME} \
        --query 'Stacks[0].Outputs[?OutputKey==`StateMachineArn`].OutputValue' --output text) \
    --query 'status' --output text

# [ ] 8 CloudWatch alarms created
aws cloudwatch describe-alarms --alarm-name-prefix ${SERVERLESS_STACK_NAME} \
    --query 'length(MetricAlarms)' --output text

# [ ] POST /orders returns 200
curl -s -o /dev/null -w "%{http_code}" -X POST \
    $(aws cloudformation describe-stacks --stack-name ${SERVERLESS_STACK_NAME} \
        --query 'Stacks[0].Outputs[?OutputKey==`ApiEndpoint`].OutputValue' --output text) \
    -H "Content-Type: application/json" \
    -d '{"customerId":"VALIDATE","items":[{"productId":"PROD-001","quantity":1,"price":79}],"totalAmount":79}'
```

#### CI/CD Pipeline Workshop

```bash
# [ ] Stack status is CREATE_COMPLETE
aws cloudformation describe-stacks --stack-name ${CICD_STACK_NAME} \
    --query 'Stacks[0].StackStatus' --output text

# [ ] 2 EC2 instances running in ASG
aws autoscaling describe-auto-scaling-groups \
    --auto-scaling-group-names ${CICD_STACK_NAME}-asg \
    --query 'AutoScalingGroups[0].Instances[*].[InstanceId,HealthStatus,LifecycleState]' \
    --output table

# [ ] ALB health check passes
curl -s -o /dev/null -w "%{http_code}" \
    $(aws cloudformation describe-stacks --stack-name ${CICD_STACK_NAME} \
        --query 'Stacks[0].Outputs[?OutputKey==`ALBEndpoint`].OutputValue' --output text)/health

# [ ] Pipeline exists and has run
aws codepipeline get-pipeline-state \
    --name ${CICD_STACK_NAME}-pipeline \
    --query 'stageStates[*].{Stage:stageName,Status:latestExecution.status}' \
    --output table

# [ ] Source artifact exists in S3
aws s3 ls s3://$(aws cloudformation describe-stacks --stack-name ${CICD_STACK_NAME} \
    --query 'Stacks[0].Outputs[?OutputKey==`ArtifactBucketName`].OutputValue' --output text)/source/app.zip

# [ ] 8 CloudWatch alarms created
aws cloudwatch describe-alarms --alarm-name-prefix ${CICD_STACK_NAME} \
    --query 'length(MetricAlarms)' --output text
```

---

## 5. Configure DevOps Agent Space

### 5.1 Create or Access Agent Space

1. Open the [AWS DevOps Agent Console](https://console.aws.amazon.com/devops-agent/)
2. Create a new Agent Space or select an existing one
3. Note the Agent Space ID for later reference

### 5.2 Add AWS Account

1. In your Agent Space, go to **Settings** > **Accounts**
2. Click **Add account**
3. Enter your AWS account ID
4. Follow the IAM role creation flow (creates a cross-account role for DevOps Agent)
5. Complete the account connection

### 5.3 Configure Resource Discovery

1. Go to **Settings** > **Resource Discovery**
2. Add a tag-based filter:
   - **Tag Key:** `devopsagent`
   - **Tag Value:** `true`
3. Save and trigger a discovery scan
4. Verify resources appear (Lambda functions, DynamoDB tables, EC2 instances, ALB, etc.)

### 5.4 Enable Telemetry Sources

Ensure the following are accessible to DevOps Agent:

| Source | Required For |
|--------|-------------|
| **CloudWatch Logs** | Lambda function logs, CodeBuild build logs |
| **CloudWatch Metrics** | Lambda, DynamoDB, API Gateway, ALB, CodeBuild, CodePipeline metrics |
| **CloudTrail** | IAM policy changes, configuration changes, API calls |
| **Step Functions** | Execution history and state machine analysis |

### 5.5 (Optional) Configure Webhook for Auto-Investigation

To automatically trigger investigations when CloudWatch alarms fire, set up the webhook integration using the [CloudWatch Alarm Webhook sample](https://github.com/aws-samples/sample-aws-devops-agent-cloudwatch).

### 5.6 (Optional) Configure Slack Integration

1. In Agent Space **Settings** > **Integrations** > **Slack**
2. Install the DevOps Agent Slack app in your workspace
3. Connect the Slack channel to your Agent Space
4. You can now trigger investigations by messaging the agent in Slack

---

## 6. Run Your First Lab

### 6.1 Serverless Workshop - Lab 1 (Lambda Timeout)

This is the simplest lab and confirms everything is working end-to-end.

```bash
cd serverless-workshop/labs/lab1-lambda-timeout/

# Step 1: Inject the failure
./inject.sh ${SERVERLESS_STACK_NAME}
# This reduces Lambda timeout to 1s and memory to 128MB

# Step 2: Generate traffic to trigger failures
../../scripts/generate-traffic.sh ${SERVERLESS_STACK_NAME} 30 1
# You should see most requests returning "FAILED"

# Step 3: Wait 2-3 minutes, then check alarms
sleep 180
aws cloudwatch describe-alarms \
    --alarm-name-prefix ${SERVERLESS_STACK_NAME} \
    --state-value ALARM \
    --query 'MetricAlarms[*].[AlarmName,StateValue,StateReason]' \
    --output table

# Step 4: Investigate with DevOps Agent
# In the web UI or Slack, ask:
# "Investigate why the order API is failing with timeout errors"

# Step 5: After reviewing the investigation, rollback
./rollback.sh ${SERVERLESS_STACK_NAME}

# Step 6: Verify recovery
../../scripts/generate-traffic.sh ${SERVERLESS_STACK_NAME} 5 2
# All requests should return "OK" now
```

### 6.2 CI/CD Workshop - Lab 1 (Build Failure)

```bash
cd cicd-pipeline-workshop/labs/lab1-build-failure/

# Step 1: Inject the failure
./inject.sh ${CICD_STACK_NAME}
# This adds a non-existent pip package and triggers the pipeline

# Step 2: Monitor the pipeline (build will fail in ~2-3 minutes)
PIPELINE_NAME=${CICD_STACK_NAME}-pipeline
watch -n 10 "aws codepipeline get-pipeline-state \
    --name ${PIPELINE_NAME} \
    --query 'stageStates[*].{Stage:stageName,Status:latestExecution.status}' \
    --output table"
# Wait until Build stage shows "Failed"
# Press Ctrl+C to exit watch

# Step 3: Check alarms
aws cloudwatch describe-alarms \
    --alarm-name-prefix ${CICD_STACK_NAME} \
    --state-value ALARM \
    --query 'MetricAlarms[*].[AlarmName,StateValue]' \
    --output table

# Step 4: Investigate with DevOps Agent
# Ask: "The CI/CD pipeline is failing at the build stage. What's wrong?"

# Step 5: Rollback
./rollback.sh ${CICD_STACK_NAME}
```

### 6.3 Suggested Lab Order

| Order | Lab | Workshop | Time | What It Demonstrates |
|-------|-----|----------|------|---------------------|
| 1 | Lab 1: Lambda Timeout | Serverless | ~5 min | Basic config change detection |
| 2 | Lab 1: Build Failure | CI/CD | ~5 min | CodeBuild log analysis |
| 3 | Lab 3: DynamoDB Throttle | Serverless | ~5 min | Cascading failure mapping |
| 4 | Lab 2: Test Failure | CI/CD | ~8 min | Multi-stage pipeline correlation |
| 5 | Lab 5: EventBridge Misconfig | Serverless | ~5 min | Silent failure detection |
| 6 | Lab 5: Pipeline Permission | CI/CD | ~5 min | IAM/CloudTrail correlation |
| 7 | Lab 4: API Gateway 5xx | Serverless | ~5 min | Code change detection |
| 8 | Lab 4: Post-Deploy Regression | CI/CD | ~12 min | Deployment-to-metric correlation |
| 9 | Lab 2: Step Functions Failure | Serverless | ~5 min | Cross-service error tracing |
| 10 | Lab 3: Deploy Health Check | CI/CD | ~10 min | Multi-layer failure (CodeDeploy + ALB) |

---

## 7. Cost Management

### 7.1 Estimated Running Costs

| Workshop | Primary Cost Drivers | Hourly Cost | Daily (8hr) |
|----------|---------------------|-------------|-------------|
| Serverless | DynamoDB provisioned capacity (3 tables x 5 RCU/WCU) | ~$1-2 | ~$8-16 |
| CI/CD | EC2 instances (2x t3.micro) + ALB | ~$2-3 | ~$16-24 |
| **Both** | | **~$3-5** | **~$24-40** |

### 7.2 Cost Optimization Tips

- **Deploy only when actively using.** Run cleanup between sessions.
- **Serverless workshop is cheaper** and faster to redeploy. Consider deploying it first.
- **CI/CD workshop takes longer to deploy** (~15 min) due to EC2 provisioning. Factor this into your schedule.
- Lambda invocations and Step Functions transitions are negligible cost during workshops.
- CloudWatch alarm costs are fixed (~$0.10/alarm/month) and negligible.

### 7.3 Monitor Costs

```bash
# Check today's estimated charges (if Cost Explorer is enabled)
aws ce get-cost-and-usage \
    --time-period Start=$(date -u +%Y-%m-%d),End=$(date -u -d tomorrow +%Y-%m-%d) \
    --granularity DAILY \
    --metrics BlendedCost \
    --filter '{"Tags":{"Key":"devopsagent","Values":["true"]}}' \
    --query 'ResultsByTime[0].Total.BlendedCost' \
    --output table 2>/dev/null || echo "Enable Cost Explorer for cost tracking"
```

---

## 8. Cleanup

**Important:** Run cleanup when you are done to stop ongoing charges.

### 8.1 Cleanup Serverless Workshop

```bash
# Using the cleanup script
cd serverless-workshop
./scripts/cleanup.sh ${SERVERLESS_STACK_NAME}

# Or manually
aws cloudformation delete-stack \
    --stack-name ${SERVERLESS_STACK_NAME} \
    --region ${AWS_REGION}

aws cloudformation wait stack-delete-complete \
    --stack-name ${SERVERLESS_STACK_NAME} \
    --region ${AWS_REGION}

echo "Serverless workshop deleted."
```

### 8.2 Cleanup CI/CD Pipeline Workshop

The CI/CD workshop requires emptying the S3 bucket before stack deletion.

```bash
# Using the cleanup script (handles S3 bucket emptying)
cd cicd-pipeline-workshop
./scripts/cleanup.sh ${CICD_STACK_NAME}

# Or manually
BUCKET_NAME=$(aws cloudformation describe-stacks \
    --stack-name ${CICD_STACK_NAME} \
    --region ${AWS_REGION} \
    --query 'Stacks[0].Outputs[?OutputKey==`ArtifactBucketName`].OutputValue' \
    --output text)

# Empty the bucket (including all versions)
aws s3 rm s3://${BUCKET_NAME} --recursive

# Delete versioned objects
aws s3api list-object-versions --bucket ${BUCKET_NAME} \
    --query '{Objects: Versions[].{Key:Key,VersionId:VersionId}}' --output json | \
    aws s3api delete-objects --bucket ${BUCKET_NAME} --delete file:///dev/stdin 2>/dev/null

# Delete markers
aws s3api list-object-versions --bucket ${BUCKET_NAME} \
    --query '{Objects: DeleteMarkers[].{Key:Key,VersionId:VersionId}}' --output json | \
    aws s3api delete-objects --bucket ${BUCKET_NAME} --delete file:///dev/stdin 2>/dev/null

# Now delete the stack
aws cloudformation delete-stack \
    --stack-name ${CICD_STACK_NAME} \
    --region ${AWS_REGION}

aws cloudformation wait stack-delete-complete \
    --stack-name ${CICD_STACK_NAME} \
    --region ${AWS_REGION}

echo "CI/CD workshop deleted."
```

### 8.3 Verify Cleanup

```bash
# Confirm both stacks are gone
for stack in ${SERVERLESS_STACK_NAME} ${CICD_STACK_NAME}; do
    STATUS=$(aws cloudformation describe-stacks --stack-name ${stack} \
        --query 'Stacks[0].StackStatus' --output text 2>&1)
    if echo "${STATUS}" | grep -q "does not exist"; then
        echo "${stack}: DELETED"
    else
        echo "${stack}: ${STATUS} (still exists!)"
    fi
done
```

---

## 9. Troubleshooting

### 9.1 Deployment Failures

**Stack stuck in `CREATE_IN_PROGRESS` for >15 minutes:**
```bash
# Check which resource is stuck
aws cloudformation describe-stack-events \
    --stack-name <stack-name> \
    --query 'StackEvents[?ResourceStatus==`CREATE_IN_PROGRESS`].[LogicalResourceId,ResourceType,Timestamp]' \
    --output table
```

**Stack in `ROLLBACK_COMPLETE`:**
```bash
# Check what failed
aws cloudformation describe-stack-events \
    --stack-name <stack-name> \
    --query 'StackEvents[?ResourceStatus==`CREATE_FAILED`].[LogicalResourceId,ResourceStatusReason]' \
    --output table

# Delete the failed stack before retrying
aws cloudformation delete-stack --stack-name <stack-name>
aws cloudformation wait stack-delete-complete --stack-name <stack-name>

# Fix the issue and redeploy
```

**IAM permission errors:**
```bash
# Check your current identity
aws sts get-caller-identity

# Verify you can create IAM roles
aws iam create-role --role-name test-delete-me \
    --assume-role-policy-document '{"Version":"2012-10-17","Statement":[]}' 2>&1
aws iam delete-role --role-name test-delete-me 2>/dev/null
```

### 9.2 Lab Script Failures

**`inject.sh` fails with "Could not find stack":**
```bash
# Verify stack name matches
aws cloudformation list-stacks \
    --stack-status-filter CREATE_COMPLETE UPDATE_COMPLETE \
    --query 'StackSummaries[*].StackName' --output table

# Pass the correct name
./inject.sh <correct-stack-name>
```

**`rollback.sh` fails after a lab:**
```bash
# Run the rollback for the specific lab again
./rollback.sh <stack-name>

# If that fails, you can always redeploy the stack to reset everything
aws cloudformation deploy \
    --template-file ../../cloudformation/<template>.yaml \
    --stack-name <stack-name> \
    --parameter-overrides ResourcePrefix=<stack-name> \
    --capabilities CAPABILITY_NAMED_IAM
```

### 9.3 CI/CD Specific Issues

**CodeDeploy agent not running on EC2:**
```bash
# Connect via SSM Session Manager
INSTANCE_ID=$(aws autoscaling describe-auto-scaling-groups \
    --auto-scaling-group-names ${CICD_STACK_NAME}-asg \
    --query 'AutoScalingGroups[0].Instances[0].InstanceId' --output text)

aws ssm start-session --target ${INSTANCE_ID}

# Inside the session:
sudo systemctl status codedeploy-agent
sudo systemctl restart codedeploy-agent
sudo journalctl -u codedeploy-agent --no-pager -n 50
```

**Pipeline source artifact missing:**
```bash
BUCKET=$(aws cloudformation describe-stacks --stack-name ${CICD_STACK_NAME} \
    --query 'Stacks[0].Outputs[?OutputKey==`ArtifactBucketName`].OutputValue' --output text)

# Check if app.zip exists
aws s3 ls s3://${BUCKET}/source/app.zip

# If missing, the custom resource Lambda may have failed. Check its logs:
aws logs tail /aws/lambda/${CICD_STACK_NAME}-source-packager --since 1h
```

### 9.4 DevOps Agent Not Finding Resources

```bash
# Verify resources have the correct tag
aws resourcegroupstaggingapi get-resources \
    --tag-filters Key=devopsagent,Values=true \
    --query 'ResourceTagMappingList[*].ResourceARN' \
    --output table
```

If no resources appear, check that the CloudFormation templates deployed with the `devopsagent=true` tag (it's included in all resource definitions).

---

## Quick Reference Card

```
DEPLOY SERVERLESS:
  cd serverless-workshop
  ./scripts/deploy.sh devops-agent-serverless

DEPLOY CI/CD:
  cd cicd-pipeline-workshop
  ./scripts/deploy.sh devops-agent-cicd

RUN A LAB:
  cd labs/lab1-xxx/
  ./inject.sh devops-agent-xxx        # Break something
  ../../scripts/generate-traffic.sh devops-agent-xxx 30 1  # Generate load
  # Wait 2-3 min for alarms, then investigate with DevOps Agent
  ./rollback.sh devops-agent-xxx      # Fix it

VALIDATE:
  ./tests/validate-stack.sh devops-agent-xxx

CLEANUP:
  ./scripts/cleanup.sh devops-agent-xxx
```
