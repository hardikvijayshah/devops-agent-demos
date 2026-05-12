# Deployment Guide: Jenkins CI/CD + ECS Deployment Failure Workshop

Step-by-step instructions to deploy, run failure scenarios, and observe AWS DevOps Agent in action.

---

## Table of Contents

1. [Prerequisites](#1-prerequisites)
2. [Deploy the Infrastructure](#2-deploy-the-infrastructure)
3. [Access Jenkins](#3-access-jenkins)
4. [Validate the Stack](#4-validate-the-stack)
5. [Run Failure Scenarios](#5-run-failure-scenarios)
6. [Observe DevOps Agent Investigation](#6-observe-devops-agent-investigation)
7. [Generate Traffic](#7-generate-traffic)
8. [Cleanup](#8-cleanup)

---

## 1. Prerequisites

### Required Tools

```bash
# Verify AWS CLI v2
aws --version
# Expected: aws-cli/2.x.x ...

# Verify Docker
docker --version
# Expected: Docker version 24.x+ or 25.x+

# Verify jq (used by scripts)
jq --version
# Expected: jq-1.6 or higher

# Verify curl
curl --version
```

### AWS Configuration

```bash
# Configure AWS credentials (if not already done)
aws configure
# Enter: Access Key ID, Secret Access Key, Region (us-east-1), Output format (json)

# Verify credentials work
aws sts get-caller-identity
# Expected output:
# {
#     "UserId": "AIDA...",
#     "Account": "111122223333",
#     "Arn": "arn:aws:iam::111122223333:user/your-user"
# }
```

### Required IAM Permissions

Your AWS user/role needs these permissions:
- `cloudformation:*` (stack operations)
- `ecs:*` (cluster, service, task operations)
- `ecr:*` (repository and image operations)
- `ec2:*` (VPC, subnets, security groups, instances)
- `elasticloadbalancing:*` (ALB, target groups)
- `iam:CreateRole`, `iam:CreateInstanceProfile`, `iam:PutRolePolicy`, `iam:PassRole`
- `cloudwatch:*` (alarms)
- `events:*` (EventBridge rules)
- `sns:*` (topics and subscriptions)
- `ssm:PutParameter`, `ssm:GetParameter`, `ssm:DeleteParameter`
- `logs:*` (CloudWatch Logs)

Or simply use a role with `AdministratorAccess` or `PowerUserAccess` + `IAMFullAccess`.

---

## 2. Deploy the Infrastructure

### Option A: Automated Deployment (Recommended)

```bash
# Navigate to the workshop directory
cd jenkins-ecs-deployment-workshop

# Make scripts executable
chmod +x scripts/*.sh scenarios/**/*.sh tests/*.sh

# Deploy with email notifications
./scripts/deploy.sh devops-agent-jenkins your-email@example.com

# Or deploy without email notifications
./scripts/deploy.sh devops-agent-jenkins
```

The script will:
1. Validate the CloudFormation template
2. Deploy the full stack (10-15 minutes)
3. Build and push the initial Docker image to ECR
4. Wait for ECS tasks to stabilize
5. Verify ALB health check returns HTTP 200

### Option B: Manual Step-by-Step Deployment

#### Step 2.1: Validate the CloudFormation Template

```bash
aws cloudformation validate-template \
    --template-body file://cloudformation/jenkins-ecs-workshop.yaml \
    --region us-east-1
```

Expected output includes `Parameters` and `Description` fields with no errors.

#### Step 2.2: Deploy the CloudFormation Stack

```bash
aws cloudformation deploy \
    --template-file cloudformation/jenkins-ecs-workshop.yaml \
    --stack-name devops-agent-jenkins \
    --parameter-overrides \
        ResourcePrefix=devops-agent-jenkins \
        AlarmEmail=your-email@example.com \
    --capabilities CAPABILITY_NAMED_IAM \
    --region us-east-1 \
    --tags devopsagent=true Workshop=jenkins-ecs-deployment
```

Wait for deployment to complete (10-15 minutes):

```bash
aws cloudformation wait stack-create-complete \
    --stack-name devops-agent-jenkins \
    --region us-east-1
```

#### Step 2.3: Verify Stack Outputs

```bash
aws cloudformation describe-stacks \
    --stack-name devops-agent-jenkins \
    --region us-east-1 \
    --query 'Stacks[0].Outputs[*].[OutputKey,OutputValue]' \
    --output table
```

Expected outputs:

| OutputKey | Description |
|-----------|-------------|
| ALBEndpoint | `http://<alb-dns-name>` |
| JenkinsURL | `http://<jenkins-ec2-ip>:8080` |
| ECRRepositoryUri | `<account-id>.dkr.ecr.us-east-1.amazonaws.com/devops-agent-jenkins-app` |
| ECSClusterName | `devops-agent-jenkins-cluster` |
| ECSServiceName | `devops-agent-jenkins-service` |
| DeploymentTopicArn | `arn:aws:sns:us-east-1:<account-id>:devops-agent-jenkins-deployments` |

#### Step 2.4: Build and Push Initial Docker Image

```bash
# Get account ID and set ECR repo URL
ACCOUNT_ID=$(aws sts get-caller-identity --query 'Account' --output text)
ECR_REPO="${ACCOUNT_ID}.dkr.ecr.us-east-1.amazonaws.com/devops-agent-jenkins-app"

# Authenticate Docker with ECR
aws ecr get-login-password --region us-east-1 | \
    docker login --username AWS --password-stdin "${ACCOUNT_ID}.dkr.ecr.us-east-1.amazonaws.com"

# Build the application image
docker build \
    --build-arg APP_VERSION=1.0.0 \
    --build-arg BUILD_NUMBER=1 \
    --build-arg COMMIT_SHA=initial \
    -t "${ECR_REPO}:1" \
    -t "${ECR_REPO}:latest" \
    app/

# Push to ECR
docker push "${ECR_REPO}:1"
docker push "${ECR_REPO}:latest"
```

#### Step 2.5: Deploy Image to ECS

```bash
# Force new deployment with the pushed image
aws ecs update-service \
    --cluster devops-agent-jenkins-cluster \
    --service devops-agent-jenkins-service \
    --force-new-deployment \
    --region us-east-1 > /dev/null

# Wait for service to stabilize
aws ecs wait services-stable \
    --cluster devops-agent-jenkins-cluster \
    --services devops-agent-jenkins-service \
    --region us-east-1
```

#### Step 2.6: Verify Application Health

```bash
# Get the ALB endpoint
ALB_ENDPOINT=$(aws cloudformation describe-stacks \
    --stack-name devops-agent-jenkins \
    --region us-east-1 \
    --query 'Stacks[0].Outputs[?OutputKey==`ALBEndpoint`].OutputValue' \
    --output text)

# Test health endpoint
curl -s "${ALB_ENDPOINT}/health" | jq .
# Expected:
# {
#   "status": "healthy",
#   "uptime": <seconds>,
#   "hostname": "<task-id>",
#   "version": "1.0.0",
#   "environment": "production"
# }

# Test root endpoint
curl -s "${ALB_ENDPOINT}/" | jq .

# Test status endpoint
curl -s "${ALB_ENDPOINT}/api/status" | jq .
```

---

## 3. Access Jenkins

### Get Jenkins Initial Admin Password

```bash
aws ssm get-parameter \
    --name '/devops-agent-jenkins/jenkins-initial-password' \
    --with-decryption \
    --query 'Parameter.Value' \
    --output text \
    --region us-east-1
```

### Access Jenkins UI

```bash
# Get Jenkins URL
JENKINS_URL=$(aws cloudformation describe-stacks \
    --stack-name devops-agent-jenkins \
    --region us-east-1 \
    --query 'Stacks[0].Outputs[?OutputKey==`JenkinsURL`].OutputValue' \
    --output text)

echo "Jenkins URL: ${JENKINS_URL}"
```

1. Open the Jenkins URL in your browser
2. Paste the initial admin password
3. Install suggested plugins
4. Create an admin user
5. Configure the pipeline job using `jenkins/Jenkinsfile`

### Configure Jenkins Pipeline Job

1. Create a new **Pipeline** job named `ecs-deploy`
2. Under **Pipeline**, select "Pipeline script from SCM" or paste the Jenkinsfile directly
3. Set parameters:
   - `ECR_REPO`: Your ECR repository URI (from stack outputs)
   - `ECS_CLUSTER`: `devops-agent-jenkins-cluster`
   - `ECS_SERVICE`: `devops-agent-jenkins-service`
   - `AWS_REGION`: `us-east-1`

---

## 4. Validate the Stack

Run the validation script to verify all components are healthy:

```bash
./tests/validate-stack.sh devops-agent-jenkins
```

Expected output:

```
============================================
Validating Jenkins ECS Workshop Stack
============================================
Stack: devops-agent-jenkins
Region: us-east-1

--- Stack Status ---
  [PASS] Stack exists: CREATE_COMPLETE

--- ECS Cluster ---
  [PASS] ECS Cluster: ACTIVE
  [PASS] ECS Running Tasks (expected 2): 2

--- ECR Repository ---
  [PASS] ECR Images: 2

--- Load Balancer ---
  [PASS] ALB Endpoint: http://devops-agent-jenkins-alb-...
  [PASS] ALB Health Check (expected 200): 200

--- Jenkins Server ---
  [PASS] Jenkins URL: http://...
  [PASS] Jenkins Accessible (expected 200): 200

--- CloudWatch Alarms ---
  [PASS] CloudWatch Alarms (expected 6): 6

--- EventBridge Rules ---
  [PASS] ECS Deploy Failure Rule: ENABLED

============================================
All validations passed!
============================================
```

---

## 5. Run Failure Scenarios

### Scenario 1: Bad Docker Image (Container Crash)

**What it does:** Pushes a Docker image with a fatal Python import error. Containers crash immediately on startup.

```bash
# Inject the failure
./scenarios/scenario1-bad-image/inject.sh devops-agent-jenkins
```

**Monitor the failure:**

```bash
# Watch ECS service events
aws ecs describe-services \
    --cluster devops-agent-jenkins-cluster \
    --services devops-agent-jenkins-service \
    --region us-east-1 \
    --query 'services[0].events[0:5].[createdAt,message]' \
    --output table

# Check stopped tasks
aws ecs list-tasks \
    --cluster devops-agent-jenkins-cluster \
    --service-name devops-agent-jenkins-service \
    --desired-status STOPPED \
    --region us-east-1

# Check CloudWatch alarms
aws cloudwatch describe-alarms \
    --alarm-name-prefix devops-agent-jenkins \
    --state-value ALARM \
    --region us-east-1 \
    --query 'MetricAlarms[*].[AlarmName,StateValue,StateReason]' \
    --output table
```

**Expected timeline:**
- 0-30s: New tasks start and immediately crash
- 30-60s: ECS retries, tasks keep crashing
- 60-120s: Circuit breaker triggers, rollback begins
- 120-180s: Previous healthy tasks restored
- 60-300s: CloudWatch alarms fire, DevOps Agent investigates

**Rollback:**

```bash
./scenarios/scenario1-bad-image/rollback.sh devops-agent-jenkins
```

---

### Scenario 2: Health Check Failure (Delayed Degradation)

**What it does:** Deploys an image that starts healthy but after 30 seconds the `/health` endpoint returns HTTP 503 (simulating a database connection pool exhaustion).

```bash
# Inject the failure
./scenarios/scenario2-health-check-fail/inject.sh devops-agent-jenkins
```

**Monitor the failure:**

```bash
# Watch ALB target health
TG_ARN=$(aws elbv2 describe-target-groups \
    --names devops-agent-jenkins-tg \
    --region us-east-1 \
    --query 'TargetGroups[0].TargetGroupArn' \
    --output text)

aws elbv2 describe-target-health \
    --target-group-arn "${TG_ARN}" \
    --region us-east-1 \
    --output table

# Check ALB returns errors
ALB_ENDPOINT=$(aws cloudformation describe-stacks \
    --stack-name devops-agent-jenkins \
    --region us-east-1 \
    --query 'Stacks[0].Outputs[?OutputKey==`ALBEndpoint`].OutputValue' \
    --output text)

curl -s -o /dev/null -w "HTTP %{http_code}\n" "${ALB_ENDPOINT}/health"
```

**Expected timeline:**
- 0-30s: New tasks pass health checks (HTTP 200)
- 30-45s: `/health` starts returning HTTP 503
- 45-90s: ALB marks targets unhealthy, deregisters them
- 90-180s: Circuit breaker triggers, rollback begins
- 180-300s: Alarms fire, DevOps Agent investigates

**Rollback:**

```bash
./scenarios/scenario2-health-check-fail/rollback.sh devops-agent-jenkins
```

---

### Scenario 3: Resource Limits (OOM Kill)

**What it does:** Deploys an image with a background thread that allocates ~10MB/second. After passing initial health checks, the container exceeds its 512MB memory limit and gets killed.

```bash
# Inject the failure
./scenarios/scenario3-resource-limits/inject.sh devops-agent-jenkins
```

**Monitor the failure:**

```bash
# Check for OOM-killed tasks
TASK_ARN=$(aws ecs list-tasks \
    --cluster devops-agent-jenkins-cluster \
    --service-name devops-agent-jenkins-service \
    --desired-status STOPPED \
    --region us-east-1 \
    --query 'taskArns[0]' \
    --output text)

aws ecs describe-tasks \
    --cluster devops-agent-jenkins-cluster \
    --tasks "${TASK_ARN}" \
    --region us-east-1 \
    --query 'tasks[0].{Status:lastStatus,StopCode:stopCode,Reason:stoppedReason}' \
    --output table

# Check memory alarm
aws cloudwatch describe-alarms \
    --alarm-names devops-agent-jenkins-ecs-memory-high \
    --region us-east-1 \
    --query 'MetricAlarms[0].[AlarmName,StateValue]' \
    --output text
```

**Expected timeline:**
- 0-45s: Tasks start normally, pass all health checks
- 45-90s: Memory leak runs, consuming ~10MB/sec
- ~90s: Tasks hit 512MB limit, OOM-killed
- 90-120s: Tasks restart, immediately start leaking again
- 120-300s: Crash loop detected, circuit breaker triggers rollback
- 180-360s: Memory alarm fires, DevOps Agent investigates

**Rollback:**

```bash
./scenarios/scenario3-resource-limits/rollback.sh devops-agent-jenkins
```

---

## 6. Observe DevOps Agent Investigation

After injecting any scenario, DevOps Agent will:

1. **Receive notification** via CloudWatch Alarm or EventBridge rule
2. **Investigate** by querying:
   - ECS service events and stopped task reasons
   - CloudWatch Logs for container output
   - ECS task definition changes (image diff)
   - ALB target health and access logs
   - CloudWatch metrics (CPU, memory, error rates)
3. **Produce findings** including:
   - Root cause identification
   - Timeline of events
   - Affected resources
   - Remediation recommendations

### Verify Alarms Are Firing

```bash
# List all alarms in ALARM state
aws cloudwatch describe-alarms \
    --alarm-name-prefix devops-agent-jenkins \
    --state-value ALARM \
    --region us-east-1 \
    --query 'MetricAlarms[*].[AlarmName,StateValue,StateUpdatedTimestamp]' \
    --output table
```

### Check EventBridge Events

```bash
# Verify the deployment failure rule exists and is enabled
aws events describe-rule \
    --name devops-agent-jenkins-ecs-deploy-failure \
    --region us-east-1 \
    --query '{Name:Name,State:State,EventPattern:EventPattern}' \
    --output yaml
```

---

## 7. Generate Traffic

Generate background traffic to make metrics more visible in CloudWatch:

```bash
# Send 100 requests with 1-second intervals
./scripts/generate-traffic.sh devops-agent-jenkins 100 1
```

This hits all application endpoints (`/health`, `/`, `/api/status`, `/api/process`, `/api/info`) and reports success/failure counts.

---

## 8. Cleanup

Remove all AWS resources created by this workshop:

```bash
./scripts/cleanup.sh devops-agent-jenkins
```

The cleanup script:
1. Deletes all ECR images (required before stack deletion)
2. Scales ECS service to 0
3. Removes SSM parameters
4. Deletes the CloudFormation stack and waits for completion

### Manual Cleanup (if script fails)

```bash
# Delete ECR images
aws ecr batch-delete-image \
    --repository-name devops-agent-jenkins-app \
    --image-ids "$(aws ecr list-images --repository-name devops-agent-jenkins-app --query 'imageIds' --output json --region us-east-1)" \
    --region us-east-1

# Scale down service
aws ecs update-service \
    --cluster devops-agent-jenkins-cluster \
    --service devops-agent-jenkins-service \
    --desired-count 0 \
    --region us-east-1

# Delete SSM parameter
aws ssm delete-parameter \
    --name '/devops-agent-jenkins/jenkins-initial-password' \
    --region us-east-1

# Delete stack
aws cloudformation delete-stack \
    --stack-name devops-agent-jenkins \
    --region us-east-1

# Wait for deletion
aws cloudformation wait stack-delete-complete \
    --stack-name devops-agent-jenkins \
    --region us-east-1
```

### Verify Cleanup

```bash
# Confirm stack is deleted
aws cloudformation describe-stacks \
    --stack-name devops-agent-jenkins \
    --region us-east-1 2>&1 | grep -q "does not exist" && echo "Stack deleted successfully"
```

---

## Troubleshooting

### Stack deployment fails with IAM error

```
CAPABILITY_NAMED_IAM is required
```

Ensure you include `--capabilities CAPABILITY_NAMED_IAM` in the deploy command.

### ECS tasks stuck in PROVISIONING

```bash
# Check if subnets have internet access (needed to pull ECR images)
aws ecs describe-tasks \
    --cluster devops-agent-jenkins-cluster \
    --tasks $(aws ecs list-tasks --cluster devops-agent-jenkins-cluster --query 'taskArns[0]' --output text --region us-east-1) \
    --region us-east-1 \
    --query 'tasks[0].{Status:lastStatus,Reason:stoppedReason}' \
    --output table
```

### Docker login fails

```bash
# Re-authenticate
aws ecr get-login-password --region us-east-1 | \
    docker login --username AWS --password-stdin \
    "$(aws sts get-caller-identity --query 'Account' --output text).dkr.ecr.us-east-1.amazonaws.com"
```

### Jenkins not responding

The Jenkins EC2 instance takes 3-5 minutes to fully start. Verify:

```bash
# Check EC2 instance status
INSTANCE_ID=$(aws cloudformation describe-stack-resources \
    --stack-name devops-agent-jenkins \
    --logical-resource-id JenkinsInstance \
    --region us-east-1 \
    --query 'StackResources[0].PhysicalResourceId' \
    --output text)

aws ec2 describe-instance-status \
    --instance-ids "${INSTANCE_ID}" \
    --region us-east-1 \
    --query 'InstanceStatuses[0].{Instance:InstanceState.Name,System:SystemStatus.Status,Instance:InstanceStatus.Status}' \
    --output table
```

### ALB health check failing after deployment

```bash
# Check target group health
TG_ARN=$(aws elbv2 describe-target-groups \
    --names devops-agent-jenkins-tg \
    --region us-east-1 \
    --query 'TargetGroups[0].TargetGroupArn' \
    --output text)

aws elbv2 describe-target-health \
    --target-group-arn "${TG_ARN}" \
    --region us-east-1 \
    --query 'TargetHealthDescriptions[*].{Target:Target.Id,Health:TargetHealth.State,Reason:TargetHealth.Reason}' \
    --output table
```
