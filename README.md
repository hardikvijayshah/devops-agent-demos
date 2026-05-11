# AWS DevOps Agent - Demo Workshops

Three production-grade, hands-on workshops demonstrating AWS DevOps Agent's full spectrum of capabilities -- reactive incident investigation AND proactive prevention. Each workshop deploys realistic application infrastructure with 5 scenarios that showcase how DevOps Agent correlates telemetry, code changes, and configuration drift to identify root causes and prevent future incidents.

---

## What is AWS DevOps Agent?

[AWS DevOps Agent](https://aws.amazon.com/devops-agent/) is an AI-powered operations assistant built on **Amazon Bedrock AgentCore**. It functions as an always-available SRE teammate that autonomously investigates incidents across AWS, multicloud, and on-premises environments.

### Core Capabilities

| Capability | Description |
|-----------|-------------|
| **Autonomous Investigation** | Triggered by CloudWatch alarms, PagerDuty alerts, or manual chat -- runs 5-8 minute deep-dive analyses |
| **Topology Intelligence** | Auto-discovers and maps resource interconnections across accounts and services |
| **Deployment Correlation** | Correlates metric anomalies with deployment timestamps and code changes |
| **Proactive Evaluations** | Weekly prevention recommendations for observability, infrastructure, and resilience |
| **Learned Skills** | Pattern recognition from past investigations to optimize future workflows |
| **Multi-Source Telemetry** | Integrates with CloudWatch, Datadog, Dynatrace, New Relic, Splunk, Grafana |

### How It Works

DevOps Agent organizes work through **Agent Spaces** -- isolated logical containers that provide cross-account access to cloud resources, telemetry, code repositories, and ticketing systems. Investigations are billed at **$0.0083/agent-second** with a free tier of 2 months.

---

## Why These Workshops Exist

After analyzing the full AWS DevOps Agent demo ecosystem (12 existing aws-samples repos and 6+ blog posts), three major gaps were identified:

| Existing Coverage | Gap Identified |
|------------------|----------------|
| EKS Workshop (5 labs) | **No serverless demo** -- Lambda + Step Functions + DynamoDB + EventBridge |
| ECS Workshop (10 labs) | **No CI/CD pipeline demo** -- CodePipeline + CodeBuild + CodeDeploy |
| SageMaker Workshop (4 labs) | **No proactive evaluations demo** -- ALL existing demos are reactive only |
| Network Incident Response (4 scenarios) | |
| Automated Incident Lifecycle | |
| CloudWatch Alarm Webhook | |
| Cross-account setup (CDK + Terraform) | |
| MCP/ACP integrations (Grafana, Salesforce, IDE) | |

These three workshops fill the largest remaining gaps, providing comprehensive coverage of serverless, CI/CD, and the completely undemonstrated **Evaluations (proactive prevention)** capability.

---

## Workshop Overview

### Workshop 1: Serverless Application Troubleshooting

A complete order processing system built on serverless services with 5 failure injection labs.

| Attribute | Detail |
|-----------|--------|
| **Infrastructure** | API Gateway, Lambda (x6), Step Functions, DynamoDB (x3), EventBridge, SQS, SNS |
| **CloudFormation Resources** | 43 resources |
| **CloudWatch Alarms** | 8 (Lambda errors, duration, SFN failures, DynamoDB throttle, API 5xx, latency, DLQ) |
| **Deploy Time** | ~5-8 minutes |
| **Estimated Cost** | ~$1-2/hour |
| **Discovery Tag** | `devopsagent = true` |

**Labs:**

| # | Scenario | Failure Type | Services Impacted | Difficulty |
|---|----------|-------------|-------------------|-----------|
| 1 | Lambda timeout and memory constraint | Configuration | Lambda, API Gateway | Beginner |
| 2 | Step Functions workflow failure (broken code) | Code Bug | Step Functions, Lambda | Intermediate |
| 3 | DynamoDB throttling cascade | Capacity | DynamoDB, Lambda, Step Functions | Intermediate |
| 4 | API Gateway 5xx (malformed Lambda responses) | Code Bug | API Gateway, Lambda | Intermediate |
| 5 | EventBridge rule misconfiguration (silent failure) | Silent Failure | EventBridge, SNS | Advanced |

### Workshop 2: CI/CD Pipeline Failure Investigation

A full deployment pipeline with a Flask web application, targeting EC2 instances behind an ALB, with 5 pipeline failure labs.

| Attribute | Detail |
|-----------|--------|
| **Infrastructure** | VPC, ALB, EC2 ASG (2 instances), CodePipeline, CodeBuild (x2), CodeDeploy, S3 |
| **CloudFormation Resources** | 39 resources |
| **CloudWatch Alarms** | 8 (build failures, test failures, pipeline failures, ALB unhealthy/5xx/latency, CPU, deploy) |
| **Deploy Time** | ~10-15 minutes |
| **Estimated Cost** | ~$2-3/hour |
| **Discovery Tag** | `devopsagent = true` |

**Labs:**

| # | Scenario | Failure Type | Pipeline Stage | Difficulty |
|---|----------|-------------|---------------|-----------|
| 1 | Build failure (missing pip dependency) | Dependency | Build | Beginner |
| 2 | Test failure (regression bugs caught by tests) | Code Bug | Test | Beginner |
| 3 | Deployment health check failure (wrong port) | Config Mismatch | Deploy | Intermediate |
| 4 | Post-deployment performance regression (latency) | Performance | Post-Deploy | Advanced |
| 5 | Pipeline stuck (IAM permission removed) | IAM/Security | Build | Advanced |

### Workshop 3: Proactive Evaluations (Prevention Mode)

**The only workshop demonstrating DevOps Agent's Evaluation capability.** Deploys intentionally under-monitored and misconfigured infrastructure, then uses Evaluations mode to discover gaps BEFORE any incident occurs.

| Attribute | Detail |
|-----------|--------|
| **Infrastructure** | API Gateway, Lambda (x3), DynamoDB (x3), ALB, EC2 ASG, EventBridge, SNS |
| **CloudFormation Resources** | 35 resources (all with intentional gaps) |
| **CloudWatch Alarms** | 3 only (intentional -- should have 10+, with lenient thresholds) |
| **Deploy Time** | ~5-8 minutes |
| **Estimated Cost** | ~$2/hour |
| **Discovery Tag** | `devopsagent = true` |
| **Agent Mode** | Evaluations (proactive), not Investigations (reactive) |

**Labs:**

| # | Focus Area | What Agent Discovers | Difficulty |
|---|-----------|---------------------|-----------|
| 1 | Observability Gaps | 8+ missing alarms, lenient thresholds, no X-Ray | Beginner |
| 2 | Capacity Planning | No DDB auto-scaling, fixed ASG, no reserved concurrency | Intermediate |
| 3 | Application Resilience | No retry logic, no DLQ, table scans, no validation | Intermediate |
| 4 | Deployment Safety | No versioning, no canary deploy, no rollback mechanism | Advanced |
| 5 | Security Posture | No API auth, no WAF, broad IAM, no encryption | Advanced |

---

## Architecture

### Serverless Workshop

```
Client
  |
  v
+-----------------+
|   API Gateway   |   REST API (POST /orders, GET /orders)
|   + CloudWatch  |   Metrics: 5XXError, Latency
+--------+--------+
         |
+--------v--------+
|     Lambda:     |   order-api (Python 3.12)
|   order-api     |   Writes to DynamoDB, starts Step Functions
+--------+--------+
         |
+--------v-----------+
|   Step Functions   |   Order Processing Workflow
|   State Machine    |   With retry logic and error handling
+--------+-----------+
         |
         +---> ValidateOrder (Lambda) ---> Inventory Table (DynamoDB)
         |
         +---> ProcessPayment (Lambda) ---> Payments Table (DynamoDB)
         |
         +---> UpdateInventory (Lambda) ---> Inventory Table (DynamoDB)
         |
         +---> SendNotification (Lambda) ---> EventBridge Custom Bus
         |                                    + SNS Topic
         |
         +---> [On Failure] ---> EventBridge (OrderFailed event)
                                     |
                                 SQS Dead Letter Queue

CloudWatch Alarms (8):
  order-api-errors          order-api-duration       sfn-failures
  dynamodb-throttle         api-5xx-errors           api-latency
  dlq-messages              validate-order-errors
```

**Data Flow:**
1. Client sends POST request to API Gateway `/orders` endpoint
2. `order-api` Lambda writes order to DynamoDB Orders table, starts Step Functions execution
3. Step Functions orchestrates: validate -> pay -> update inventory -> notify
4. On success: EventBridge publishes `OrderCompleted`, SNS sends notification
5. On failure: EventBridge publishes `OrderFailed`, message routes to SQS DLQ

**Seed Data:** CloudFormation custom resource automatically populates the Inventory table with 5 sample products (PROD-001 through PROD-005).

### CI/CD Pipeline Workshop

```
+------------------+     +------------------+     +------------------+     +------------------+
|     Source       |---->|      Build       |---->|      Test        |---->|     Deploy       |
|  S3 Bucket      |     |  CodeBuild       |     |  CodeBuild       |     |  CodeDeploy      |
|  (versioned)    |     |  python:3.12     |     |  unittest        |     |  AllAtOnce       |
+------------------+     +------------------+     +------------------+     +--------+---------+
                                                                                   |
                                                                          +--------v---------+
                                                                          |  Auto Scaling    |
                                                                          |  Group           |
                                                                          |  2x t3.micro     |
                                                                          |  Amazon Linux    |
                                                                          |  2023            |
                                                                          +--------+---------+
                                                                                   |
                                                                          +--------v---------+
                                                                          |     ALB          |
                                                                          |  Port 80 -> 5000 |
                                                                          |  /health check   |
                                                                          +------------------+

VPC: 10.0.0.0/16
  Public Subnet 1: 10.0.1.0/24 (AZ-a)
  Public Subnet 2: 10.0.2.0/24 (AZ-b)
  Internet Gateway + Route Table

CloudWatch Alarms (8):
  build-failures       test-failures        pipeline-failures    deploy-failures
  alb-unhealthy        alb-5xx              alb-latency          cpu-utilization

Pipeline Notifications: SNS topic + CodeStar Notification Rule
Auto-Rollback: CodeDeploy rolls back on deployment failure or ALB alarm
```

**Pipeline Flow:**
1. Source artifact (app.zip) uploaded to S3 triggers pipeline
2. Build stage: installs dependencies, compiles Python, produces artifact
3. Test stage: runs unittest suite against the Flask app
4. Deploy stage: CodeDeploy pushes to EC2 instances (install deps -> start gunicorn -> validate health)
5. ALB monitors application health on port 5000 `/health` endpoint

**Application:** Flask web app with 4 endpoints (`/health`, `/`, `/api/status`, `/api/process`), served by gunicorn with 2 workers on port 5000.

---

## Prerequisites

### Required

| Requirement | Details |
|-------------|---------|
| **AWS CLI v2** | Configured with credentials (`aws configure`) |
| **AWS Account Permissions** | IAM, Lambda, API Gateway, Step Functions, DynamoDB, SQS, SNS, EventBridge, CloudWatch, VPC, EC2, ALB, CodePipeline, CodeBuild, CodeDeploy, S3, CloudFormation |
| **AWS DevOps Agent** | Agent Space configured in your account |
| **Shell Utilities** | `bash`, `curl`, `zip` (Linux, macOS, or Windows WSL) |

### Recommended

| Requirement | Details |
|-------------|---------|
| **Region** | `us-east-1` (default, all services available) |
| **CloudTrail** | Enabled for configuration and IAM change detection |
| **DevOps Agent Webhook** | CloudWatch Alarm -> SNS -> Lambda -> DevOps Agent webhook for automatic investigations |

### IAM Permissions Needed

The deploying user/role needs permissions to:
- Create and manage CloudFormation stacks with `CAPABILITY_NAMED_IAM`
- Create IAM roles and policies (named roles are used for clarity)
- Create all resources listed above for the chosen workshop

### DevOps Agent Space Setup

1. Navigate to the [AWS DevOps Agent console](https://console.aws.amazon.com/devops-agent/)
2. Create a new Agent Space (or use an existing one)
3. Add the target AWS account as a monitored account
4. Configure tag-based resource discovery with filter: `devopsagent = true`
5. Ensure CloudWatch Logs, Metrics, and CloudTrail access is enabled
6. (Optional) Configure Slack integration for investigation notifications

---

## Quick Start

### Deploy Serverless Workshop

```bash
cd serverless-workshop

# Deploy with defaults (stack: devops-agent-serverless, region: us-east-1)
./scripts/deploy.sh

# Or with custom name and alarm email
./scripts/deploy.sh my-serverless user@example.com

# Or in a specific region
export AWS_REGION=us-west-2
./scripts/deploy.sh
```

### Deploy CI/CD Pipeline Workshop

```bash
cd cicd-pipeline-workshop

# Deploy with defaults (stack: devops-agent-cicd, region: us-east-1)
./scripts/deploy.sh

# Or with custom name and alarm email
./scripts/deploy.sh my-cicd-workshop user@example.com
```

### Deploy Proactive Evaluations Workshop

```bash
cd proactive-evaluations-workshop

# Deploy with defaults (stack: devops-eval, region: us-east-1)
./scripts/deploy.sh

# Or with custom name
./scripts/deploy.sh my-eval-workshop user@example.com
```

### Validate Deployment

```bash
# Verify all resources are healthy
cd serverless-workshop && ./tests/validate-stack.sh
cd cicd-pipeline-workshop && ./tests/validate-stack.sh
cd proactive-evaluations-workshop && ./tests/validate-stack.sh
```

---

## How Each Lab Works

Every lab follows the same inject-observe-rollback pattern:

```
+------------+     +------------------+     +---------------+     +------------------+     +------------+
|  inject.sh |---->| generate-traffic |---->| CW Alarms     |---->| DevOps Agent     |---->| rollback.sh|
|            |     | .sh              |     | fire (2-3 min)|     | investigates     |     |            |
+------------+     +------------------+     +---------------+     +------------------+     +------------+
```

### Step-by-Step

1. **Navigate** to the lab directory: `cd labs/lab1-lambda-timeout/`

2. **Inject the failure:**
   ```bash
   ./inject.sh [stack-name]
   ```
   Each inject script makes a specific change (config tweak, code swap, permission removal) and prints exactly what was changed and what to expect.

3. **Generate traffic** (triggers the failure):
   ```bash
   ../../scripts/generate-traffic.sh [stack-name] [count] [interval]
   ```
   Sends realistic requests to the application. Default: 20 requests, 2s apart.

4. **Wait for CloudWatch Alarms** to enter ALARM state (typically 2-3 minutes):
   ```bash
   aws cloudwatch describe-alarms \
       --alarm-name-prefix [stack-name] \
       --state-value ALARM \
       --query 'MetricAlarms[*].[AlarmName,StateValue]' \
       --output table
   ```

5. **Investigate with DevOps Agent:**
   - **Web UI:** Open your Agent Space and start an investigation
   - **Slack:** Ask the agent directly (e.g., *"Why is the order API failing?"*)
   - **Webhook:** If configured, the alarm automatically triggers an investigation

6. **Compare findings** with the expected results documented in each lab's README.

7. **Rollback** to restore the working state:
   ```bash
   ./rollback.sh [stack-name]
   ```

---

## DevOps Agent Capabilities Demonstrated

### Capability Matrix

| Capability | Serverless | CI/CD | Evaluations | Description |
|-----------|:---------:|:-----:|:-----------:|-------------|
| CloudWatch Logs Insights | 1, 2, 3, 4 | 1, 2 | 3 | Query and analyze Lambda/CodeBuild log streams |
| CloudWatch Metrics correlation | 1, 3, 5 | 3, 4 | 1, 2 | Correlate error spikes with resource metrics |
| Configuration change detection | 1, 3, 5 | 5 | 1, 2, 4 | Detect config, throughput, and IAM changes |
| Code change correlation | 2, 4 | 1, 2, 3, 4 | 3, 4 | Link deployments to failure onset |
| Cascading failure mapping | 3 | 3 | - | Trace failures across service chain |
| Silent failure detection | 5 | - | 5 | Identify absence of expected behavior |
| Deployment-to-metric correlation | - | 3, 4 | 4 | Connect deploy timestamps to health changes |
| IAM/CloudTrail analysis | - | 5 | 5 | Detect IAM policy weaknesses |
| Pipeline stage analysis | - | 1, 2, 3, 5 | - | Identify which stage failed and why |
| **Proactive evaluation** | - | - | All | Identify gaps BEFORE incidents occur |
| **Observability gap detection** | - | - | 1 | Find missing alarms and lenient thresholds |
| **Capacity planning** | - | - | 2 | Detect under-provisioned resources |
| **Resilience assessment** | - | - | 3 | Find missing retry, DLQ, validation patterns |
| **Deployment safety audit** | - | - | 4 | Identify missing rollback/canary mechanisms |
| **Security posture review** | - | - | 5 | Find auth, encryption, and IAM gaps |

### Investigation Quality Indicators

When DevOps Agent investigates each lab scenario, look for these quality markers:
- **Root cause accuracy:** Does it identify the exact change that caused the failure?
- **Evidence trail:** Does it cite specific log lines, metric data points, or CloudTrail events?
- **Correlation timeline:** Does it connect the timing of the change to the onset of symptoms?
- **Actionable recommendation:** Does it suggest a specific fix (not just "check the logs")?

---

## Repository Structure

```
devops-agent-demos/
|
+-- README.md                                    # This file
|
+-- serverless-workshop/
|   +-- README.md                                # Workshop-specific guide
|   +-- cloudformation/
|   |   +-- serverless-workshop.yaml             # 43 resources (API GW, Lambda, SFN, DDB, EB, SQS, SNS, CW)
|   +-- labs/
|   |   +-- lab1-lambda-timeout/
|   |   |   +-- inject.sh                        # Reduces Lambda timeout to 1s, memory to 128MB
|   |   |   +-- rollback.sh                      # Restores timeout to 30s, memory to 256MB
|   |   |   +-- README.md                        # Scenario description, steps, expected findings
|   |   +-- lab2-stepfunctions-failure/
|   |   |   +-- inject.sh                        # Deploys broken Lambda code (KeyError)
|   |   |   +-- rollback.sh                      # Restores original validation code
|   |   |   +-- README.md
|   |   +-- lab3-dynamodb-throttle/
|   |   |   +-- inject.sh                        # Reduces DynamoDB to 1 RCU/WCU
|   |   |   +-- rollback.sh                      # Restores 5 RCU/WCU
|   |   |   +-- README.md
|   |   +-- lab4-api-gateway-errors/
|   |   |   +-- inject.sh                        # Deploys Lambda returning malformed responses
|   |   |   +-- rollback.sh                      # Restores original order-api code
|   |   |   +-- README.md
|   |   +-- lab5-eventbridge-misconfig/
|   |       +-- inject.sh                        # Changes EventBridge rule to non-matching pattern
|   |       +-- rollback.sh                      # Restores correct event pattern
|   |       +-- README.md
|   +-- scripts/
|   |   +-- deploy.sh                            # CloudFormation deploy with validation
|   |   +-- cleanup.sh                           # Stack deletion
|   |   +-- generate-traffic.sh                  # Sends randomized order requests via curl
|   +-- tests/
|       +-- validate-stack.sh                    # Verifies all resources, seed data, and connectivity
|
+-- cicd-pipeline-workshop/
    +-- README.md                                # Workshop-specific guide
    +-- cloudformation/
    |   +-- cicd-workshop.yaml                   # 39 resources (VPC, ALB, EC2, Pipeline, Build, Deploy)
    +-- app/
    |   +-- app.py                               # Flask web application (4 endpoints)
    |   +-- requirements.txt                     # flask, gunicorn
    |   +-- tests/
    |   |   +-- test_app.py                      # 4 unittest test cases
    |   +-- buildspec-build.yml                  # CodeBuild build spec (install + compile)
    |   +-- buildspec-test.yml                   # CodeBuild test spec (unittest)
    |   +-- appspec.yml                          # CodeDeploy deployment spec
    +-- labs/
    |   +-- lab1-build-failure/
    |   |   +-- inject.sh                        # Adds nonexistent pip package to requirements.txt
    |   |   +-- rollback.sh                      # Restores original source and triggers pipeline
    |   |   +-- README.md
    |   +-- lab2-test-failure/
    |   |   +-- inject.sh                        # Introduces API regression bugs caught by tests
    |   |   +-- rollback.sh
    |   |   +-- README.md
    |   +-- lab3-deploy-health-check/
    |   |   +-- inject.sh                        # Changes start script to use wrong port (8080 vs 5000)
    |   |   +-- rollback.sh
    |   |   +-- README.md
    |   +-- lab4-post-deploy-regression/
    |   |   +-- inject.sh                        # Adds time.sleep() delays to all endpoints
    |   |   +-- rollback.sh
    |   |   +-- README.md
    |   +-- lab5-pipeline-permission/
    |       +-- inject.sh                        # Adds explicit S3 Deny to CodeBuild IAM role
    |       +-- rollback.sh                      # Restores S3 Allow permissions
    |       +-- README.md
    +-- scripts/
    |   +-- deploy.sh                            # CloudFormation deploy + initial pipeline trigger
    |   +-- cleanup.sh                           # S3 bucket empty + stack deletion
    |   +-- generate-traffic.sh                  # Sends requests to ALB endpoints
    +-- tests/
        +-- validate-stack.sh                    # Verifies VPC, ALB, ASG, pipeline, alarms
|
+-- proactive-evaluations-workshop/
    +-- README.md                                # Workshop-specific guide
    +-- cloudformation/
    |   +-- evaluations-workshop.yaml            # 35 resources (API GW, Lambda, DDB, ALB, ASG - all with gaps)
    +-- labs/
    |   +-- lab1-observability-gaps/
    |   |   +-- inject.sh                        # Generates traffic to make metric gaps visible
    |   |   +-- rollback.sh                      # No changes to revert (gaps are by design)
    |   |   +-- README.md
    |   +-- lab2-capacity-planning/
    |   |   +-- inject.sh                        # Burst traffic to stress provisioned capacity
    |   |   +-- rollback.sh
    |   |   +-- README.md
    |   +-- lab3-resilience-weaknesses/
    |   |   +-- inject.sh                        # Malformed requests exposing missing validation
    |   |   +-- rollback.sh
    |   |   +-- README.md
    |   +-- lab4-deployment-safety/
    |   |   +-- inject.sh                        # Deploys broken code (no rollback exists)
    |   |   +-- rollback.sh                      # Manual code restore (proving the gap)
    |   |   +-- README.md
    |   +-- lab5-security-posture/
    |       +-- inject.sh                        # Demonstrates unauthenticated access, abuse
    |       +-- rollback.sh
    |       +-- README.md
    +-- scripts/
    |   +-- deploy.sh                            # CloudFormation deploy
    |   +-- cleanup.sh                           # Stack deletion
    |   +-- generate-traffic.sh                  # Order + inventory requests
    +-- tests/
        +-- validate-stack.sh                    # Verifies resources + intentional gaps exist
```

**Total: 68 files** (3 CloudFormation templates, 7 app files, 30 shell scripts, 18 READMEs, 3 publication files, 7 support files)

---

## CloudFormation Resources Deployed

### Serverless Workshop (43 resources)

| Category | Resources | Count |
|----------|-----------|-------|
| **DynamoDB** | Orders, Inventory, Payments tables (provisioned mode, 5 RCU/WCU each) | 3 |
| **Lambda** | order-api, validate-order, process-payment, update-inventory, send-notification, seed-data | 6 |
| **Lambda Permissions** | API Gateway invoke permission | 1 |
| **CloudWatch Log Groups** | One per Lambda function (7-day retention) | 5 |
| **Step Functions** | Order workflow state machine (with X-Ray tracing) | 1 |
| **API Gateway** | REST API, /orders resource, POST + GET methods, deployment, stage (with tracing) | 6 |
| **EventBridge** | Custom bus, OrderCompleted rule, OrderFailed rule | 3 |
| **SQS** | Dead letter queue (14-day retention) | 1 |
| **SNS** | Notification topic, alarm topic, email subscription (conditional) | 2-3 |
| **IAM** | Lambda execution role, Step Functions role, API Gateway log role | 3 |
| **Resource Policies** | SNS topic policy (EventBridge), SQS queue policy (EventBridge) | 2 |
| **CloudWatch Alarms** | Lambda errors (x2), Lambda duration, SFN failures, DynamoDB throttle, API 5xx, API latency, DLQ messages | 8 |
| **Custom Resource** | Seed data (populates inventory with 5 products) | 1 |

### CI/CD Pipeline Workshop (39 resources)

| Category | Resources | Count |
|----------|-----------|-------|
| **VPC/Networking** | VPC, 2 public subnets, IGW, route table, public route, 2 route table associations | 7 |
| **Security Groups** | ALB SG (port 80 inbound), EC2 SG (port 5000 from ALB only) | 2 |
| **Load Balancer** | ALB, target group (/health check), listener (port 80) | 3 |
| **Compute** | Launch template (AL2023, CodeDeploy agent userdata), Auto Scaling Group (2 instances) | 2 |
| **CI/CD** | CodePipeline (4 stages), CodeBuild build project, CodeBuild test project, CodeDeploy app, deployment group | 5 |
| **Storage** | S3 artifact bucket (versioned, lifecycle policy) | 1 |
| **IAM** | EC2 instance role + profile, CodeBuild role, CodeDeploy role, CodePipeline role, source packager role | 6 |
| **Lambda** | Source packager function (custom resource to create initial app.zip) | 1 |
| **SNS** | Alarm topic, pipeline notification topic, email subscription (conditional) | 2-3 |
| **Notifications** | CodeStar notification rule (pipeline events) | 1 |
| **CloudWatch Alarms** | Build failures, test failures, pipeline failures, deploy failures, ALB unhealthy, ALB 5xx, ALB latency, CPU utilization | 8 |

---

## Cost Breakdown

### Serverless Workshop (~$1-2/hour)

| Service | Cost Driver | Estimate |
|---------|------------|----------|
| DynamoDB | 3 tables x 5 RCU/WCU provisioned | ~$0.50/hr |
| Lambda | Invocations during traffic generation | ~$0.01/hr |
| API Gateway | REST API requests | ~$0.01/hr |
| Step Functions | State transitions | ~$0.01/hr |
| CloudWatch | Alarms + log storage | ~$0.10/hr |

### CI/CD Pipeline Workshop (~$2-3/hour)

| Service | Cost Driver | Estimate |
|---------|------------|----------|
| EC2 | 2x t3.micro instances | ~$1.04/hr |
| ALB | Load balancer + LCU | ~$0.50/hr |
| CodeBuild | Build minutes (general1.small) | ~$0.01/build |
| S3 | Artifact storage | ~$0.01/hr |
| CloudWatch | Alarms + log storage | ~$0.10/hr |

### Proactive Evaluations Workshop (~$2/hour)

| Service | Cost Driver | Estimate |
|---------|------------|----------|
| EC2 | 2x t3.micro instances | ~$1.04/hr |
| ALB | Load balancer + LCU | ~$0.50/hr |
| DynamoDB | 3 tables provisioned | ~$0.15/hr |
| Lambda | Invocations (minimal) | ~$0.01/hr |
| CloudWatch | 3 alarms + logs | ~$0.05/hr |

**Important:** Remember to run `cleanup.sh` when done to avoid ongoing charges.

---

## Cleanup

```bash
# Serverless workshop
cd serverless-workshop
./scripts/cleanup.sh [stack-name]

# CI/CD pipeline workshop (empties S3 bucket first, then deletes stack)
cd cicd-pipeline-workshop
./scripts/cleanup.sh [stack-name]

# Proactive evaluations workshop
cd proactive-evaluations-workshop
./scripts/cleanup.sh [stack-name]
```

All cleanup scripts prompt for confirmation before deleting.

---

## Troubleshooting

### Common Issues

| Problem | Workshop | Solution |
|---------|----------|----------|
| Stack fails with IAM error | Both | Ensure deploying user has `iam:CreateRole` and `iam:PutRolePolicy` permissions |
| Resources not visible in Agent Space | Both | Verify `devopsagent=true` tag filter is configured in your Agent Space |
| Alarms not triggering | Both | Generate more traffic with shorter intervals; some alarms need 2+ evaluation periods |
| EC2 instances not healthy | CI/CD | Wait 5 minutes for boot + CodeDeploy agent install; check SG allows ALB -> port 5000 |
| Pipeline not starting | CI/CD | Verify `source/app.zip` exists in S3 bucket (custom resource should create it) |
| CodeDeploy agent not running | CI/CD | Connect via Session Manager: `sudo systemctl status codedeploy-agent` |
| First pipeline run fails | CI/CD | EC2 instances may not be ready; wait for healthy targets, then retry pipeline |
| Rollback doesn't restore alarms to OK | Both | Alarms need 1-2 evaluation periods of healthy data to return to OK state |

### Verifying Cleanup

After running `cleanup.sh`, confirm no resources remain:
```bash
aws cloudformation describe-stacks --stack-name [stack-name] 2>&1 | grep -q "does not exist" && echo "Clean" || echo "Stack still exists"
```

---

## Related Resources

### Official AWS DevOps Agent

- [AWS DevOps Agent Product Page](https://aws.amazon.com/devops-agent/)
- [AWS DevOps Agent Documentation](https://docs.aws.amazon.com/devops-agent/latest/userguide/)
- [Pricing](https://aws.amazon.com/devops-agent/pricing/)

### Existing AWS Sample Workshops (This Repo Fills the Gaps)

| Category | Repo | Coverage |
|----------|------|----------|
| **Workshops** | [EKS Workshop](https://github.com/aws-samples/sample-devops-agent-eks-workshop) | 5 labs, retail microservices on EKS |
| | [ECS Workshop](https://github.com/aws-samples/sample-devops-agent-ecs-workshop) | 10 labs, retail microservices on ECS |
| | [SageMaker Workshop](https://github.com/aws-samples/sample-sagemaker-devops-agent-troubleshooting-workshop) | 4 labs, ML ops |
| **Incident Response** | [Network Incident Response](https://github.com/aws-samples/sample-automated-aws-devops-agent-network-incident-response) | 4 network failure scenarios |
| | [Automated Incident Lifecycle](https://github.com/aws-samples/sample-automated-incident-lifecycle-with-aws-devops-agent) | End-to-end detect/investigate/mitigate |
| **IaC Setup** | [Cross-Account CDK](https://github.com/aws-samples/sample-aws-devops-agent-cdk) | Agent Space with CDK |
| | [Cross-Account Terraform](https://github.com/aws-samples/sample-aws-devops-agent-terraform) | Agent Space with Terraform |
| **Integrations** | [CloudWatch Alarm Webhook](https://github.com/aws-samples/sample-aws-devops-agent-cloudwatch) | Alarm-to-agent automation |
| | [ACP/MCP IDE Integration](https://github.com/aws-samples/sample-aws-devops-agent-acp-mcp) | 19 tools for IDE integration |
| | [Grafana MCP Integration](https://github.com/aws-samples/sample-aws-devops-agent-ecs-grafana-mcp) | ECS + Grafana MCP |

**Gaps filled by this repo:**
- Serverless troubleshooting (Lambda, Step Functions, API Gateway, DynamoDB, EventBridge)
- CI/CD pipeline investigation (CodePipeline, CodeBuild, CodeDeploy)
- Proactive Evaluations (the ONLY demo of DevOps Agent's prevention mode)

---

## License

MIT-0
