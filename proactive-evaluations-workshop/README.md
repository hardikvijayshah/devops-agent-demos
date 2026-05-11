# AWS DevOps Agent - Proactive Evaluations Workshop

Hands-on workshop demonstrating AWS DevOps Agent's **Evaluation (proactive prevention)** capabilities. Unlike reactive investigation workshops, this workshop deploys intentionally under-monitored and misconfigured infrastructure, then uses DevOps Agent's Evaluation mode to discover observability gaps, capacity risks, resilience weaknesses, deployment safety issues, and security posture problems -- all **before** any incident occurs.

This is the **only workshop** demonstrating DevOps Agent's proactive prevention capabilities. All other existing workshops focus exclusively on reactive incident investigation.

---

## Architecture

### System Overview

```
Client (curl / generate-traffic.sh)
  |
  v
+---------------------------+        +---------------------------+
|     API Gateway           |        |     ALB (port 80)         |
|     POST /orders          |        |     /health               |
|     GET  /inventory       |        |     /                     |
|     (NO auth, NO WAF,     |        +-------------+-------------+
|      NO throttling)       |                      |
+-------------+-------------+        +-------------v-------------+
              |                      |   Auto Scaling Group      |
              v                      |   2x t3.micro (FIXED)     |
+-------------+-------------+        |   NO scaling policy       |
|     Lambda Functions      |        |   Flask + gunicorn:8080   |
|                           |        +---------------------------+
|  order-processor:         |
|    128MB, 300s timeout    |
|    NO DLQ, NO X-Ray       |       Data Stores:
|    NO reserved concurrency|       +---------------------------+
|    NO retry logic         |       | DynamoDB (PROVISIONED)    |
|                           |       |   Orders:  5 WCU / 5 RCU  |
|  inventory-checker:       |       |   Inventory: 3 WCU / 3 RCU|
|    Full table SCAN        |       |   Sessions: 10 WCU/10 RCU |
|    NO pagination          |       |   NO auto-scaling         |
|                           |       |   NO throttle alarms      |
|  session-cleanup:         |       +---------------------------+
|    Redundant (TTL exists) |
|    900s timeout           |       Monitoring:
+---------------------------+       +---------------------------+
                                    | CloudWatch Alarms (3 only)|
                                    |   Lambda errors: >= 50    |
                                    |   ALB unhealthy: >= 2     |
                                    |   API 5xx: >= 100         |
                                    |   (LENIENT thresholds)    |
                                    |                           |
                                    |  MISSING:                 |
                                    |   - DDB throttle alarm    |
                                    |   - Lambda duration alarm |
                                    |   - Lambda throttle alarm |
                                    |   - ALB latency alarm     |
                                    |   - API latency alarm     |
                                    |   - ASG CPU alarm         |
                                    |   - Request anomaly alarm |
                                    +---------------------------+
```

### Intentional Gaps Summary

| Category | Gap Count | Examples |
|----------|-----------|---------|
| **Observability** | 8+ missing alarms | No DynamoDB throttle, no Lambda duration, no latency alarms |
| **Capacity** | 4 issues | Fixed ASG, no DDB auto-scaling, no reserved concurrency |
| **Resilience** | 6 issues | No retry logic, no DLQ, no input validation, table scans |
| **Deployment** | 5 issues | No versioning, no canary deploy, no rollback mechanism |
| **Security** | 8+ issues | No API auth, no WAF, no encryption, broad IAM |

---

## CloudFormation Resources (35 total)

| Category | Resource | Type | Intentional Gap |
|----------|----------|------|-----------------|
| **VPC** | VPC, IGW, 2 Subnets, Route Table | Standard | None (networking is correct) |
| **Security Groups** | ALB SG, App SG | EC2::SecurityGroup | No WAF on ALB |
| **DynamoDB** | OrdersTable | DynamoDB::Table | 5 WCU, no auto-scaling |
| | InventoryTable | DynamoDB::Table | 3 WCU, no auto-scaling |
| | SessionsTable | DynamoDB::Table | TTL enabled (cleanup function is redundant) |
| **Lambda** | OrderProcessorFunction | Lambda::Function | 128MB, 300s, no DLQ, no X-Ray, no retry |
| | InventoryCheckerFunction | Lambda::Function | Full table scan, no pagination |
| | SessionCleanupFunction | Lambda::Function | Redundant, 900s timeout, scan+delete |
| | SeedDataFunction | Lambda::Function | Custom resource for seed data |
| **API Gateway** | RestApi, Resources, Methods, Stage | ApiGateway | No auth, no throttling, no WAF, no validation |
| **ALB** | ALB, TargetGroup, Listener | ELBv2 | No latency alarm |
| **Compute** | LaunchTemplate, ASG | EC2/AutoScaling | Fixed size (Min=Max=2), no scaling policy |
| **IAM** | LambdaExecutionRole | IAM::Role | Overly broad (Scan, DeleteItem) |
| | EC2Role + Profile | IAM::Role | Minimal (intentionally correct) |
| | SeedDataRole | IAM::Role | Minimal |
| **SNS** | NotificationTopic | SNS::Topic | No encryption |
| | AlarmNotificationTopic | SNS::Topic | No encryption |
| **EventBridge** | InventoryCheckRule | Events::Rule | Triggers scan every 5 min |
| | SessionCleanupRule | Events::Rule | Redundant cleanup every hour |
| **CloudWatch** | 3 Alarms | CloudWatch::Alarm | Only 3 (should be 10+), lenient thresholds |
| | 3 Log Groups | Logs::LogGroup | 7-day retention |

---

## Labs

| Lab | Focus Area | Evaluation Target | Gaps Found | Difficulty |
|-----|-----------|-------------------|-----------|-----------|
| **1** | [Observability Gaps](labs/lab1-observability-gaps/) | Missing alarms, lenient thresholds, no tracing | 8+ missing alarms, 3 lenient thresholds | Beginner |
| **2** | [Capacity Planning](labs/lab2-capacity-planning/) | Auto-scaling, provisioned throughput, concurrency | DDB scaling, ASG policy, Lambda concurrency | Intermediate |
| **3** | [Resilience Weaknesses](labs/lab3-resilience-weaknesses/) | Retry logic, DLQ, error handling, code quality | No retry, no DLQ, table scans, no validation | Intermediate |
| **4** | [Deployment Safety](labs/lab4-deployment-safety/) | Rollback, canary deploy, validation | No versioning, no CodeDeploy, no pre-deploy test | Advanced |
| **5** | [Security Posture](labs/lab5-security-posture/) | API auth, IAM, encryption, WAF | No auth, broad IAM, no WAF, no encryption | Advanced |

### Lab Flow

```bash
# 1. Navigate to the lab
cd labs/lab1-observability-gaps/

# 2. Run the inject script (generates traffic, shows gaps)
./inject.sh [stack-name]

# 3. Wait 5 minutes for metrics to aggregate

# 4. Trigger DevOps Agent Evaluation
aws devops-agent create-backlog-task \
    --agent-space-id <your-space-id> \
    --task-type EVALUATION \
    --title "Evaluate observability posture for devops-eval resources" \
    --priority HIGH

# 5. Monitor evaluation progress
aws devops-agent list-executions \
    --agent-space-id <your-space-id> \
    --query 'executions[?status==`RUNNING`]'

# 6. Review recommendations in Ops Backlog
aws devops-agent list-recommendations \
    --agent-space-id <your-space-id> \
    --status PROPOSED

# 7. Get agent-ready spec for a recommendation
aws devops-agent get-recommendation \
    --agent-space-id <your-space-id> \
    --recommendation-id <rec-id>

# 8. Accept or reject recommendations
aws devops-agent update-recommendation \
    --agent-space-id <your-space-id> \
    --recommendation-id <rec-id> \
    --status ACCEPTED

# 9. Rollback if needed (Lab 4 only)
./rollback.sh [stack-name]
```

---

## DevOps Agent Evaluations - How It Works

```
+------------------+     +-------------------+     +-------------------+
|   Define Goal    |     |  Scheduled Eval   |     |  Recommendations  |
|                  |     |  (or on-demand)   |     |  in Ops Backlog   |
|  "Improve        |---->|                   |---->|                   |
|   observability  |     |  Agent analyzes:  |     |  - Title          |
|   for tagged     |     |  - CloudWatch     |     |  - Priority       |
|   resources"     |     |  - Config         |     |  - Agent-Ready    |
|                  |     |  - Past incidents |     |    Spec (100K ch) |
+------------------+     |  - Code repos     |     |  - Accept/Reject  |
                         +-------------------+     +-------------------+
                                                           |
                                                   +-------v-----------+
                                                   |  Handoff to       |
                                                   |  Coding Agent     |
                                                   |  (Kiro, Claude)   |
                                                   |                   |
                                                   |  Implements fix   |
                                                   +-------------------+
```

### Evaluation vs. Investigation

| Aspect | Investigation (Reactive) | Evaluation (Proactive) |
|--------|--------------------------|------------------------|
| Trigger | Alarm fires, incident created | Scheduled (weekly) or on-demand |
| Goal | Find root cause of active problem | Prevent future problems |
| Input | Current telemetry + alarms | Historical patterns + configuration |
| Output | Mitigation plan | Recommendations with agent-ready specs |
| Timing | Immediate response | Before any incident occurs |
| This Workshop | - | All 5 labs |

---

## Prerequisites

| Requirement | Details |
|-------------|---------|
| **AWS CLI v2** | Configured with `aws configure` |
| **Permissions** | IAM, Lambda, API Gateway, DynamoDB, EC2, ALB, CloudWatch, CloudFormation, EventBridge, SNS |
| **DevOps Agent** | Agent Space with Evaluations enabled, tag discovery (`devopsagent = true`) |
| **Utilities** | `bash`, `curl`, `zip` |
| **Region** | `us-east-1` recommended |

---

## Deployment

```bash
# Default deployment
./scripts/deploy.sh

# Custom stack name + alarm email
./scripts/deploy.sh my-eval-workshop user@example.com

# Specific region
export AWS_REGION=us-west-2
./scripts/deploy.sh
```

**Deployment time:** ~5-8 minutes
**Estimated cost:** ~$2-3/hour (EC2 instances + DynamoDB provisioned capacity)

### Validate

```bash
./tests/validate-stack.sh [stack-name]
```

---

## Cost Breakdown

| Service | Cost Driver | Estimate |
|---------|------------|----------|
| EC2 | 2x t3.micro | ~$1.04/hr |
| ALB | Load balancer hour | ~$0.50/hr |
| DynamoDB | 3 tables provisioned | ~$0.15/hr |
| Lambda | Invocations (minimal) | ~$0.01/hr |
| CloudWatch | 3 alarms + logs | ~$0.05/hr |
| **Total** | | **~$2/hr** |

---

## Cleanup

```bash
./scripts/cleanup.sh [stack-name]
```

---

## Troubleshooting

| Problem | Solution |
|---------|----------|
| Evaluation not running | Verify Agent Space has evaluation schedule enabled |
| No recommendations generated | Ensure resource tags match Agent Space discovery filter |
| Lambda errors on deploy | Wait 30s for function to become Active |
| API Gateway 403 | Check stage is deployed; run stack update if needed |
| ALB unhealthy on deploy | Wait 2-3 min for instance boot + gunicorn start |
