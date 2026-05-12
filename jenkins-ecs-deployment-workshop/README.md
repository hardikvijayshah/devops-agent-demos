# AWS DevOps Agent: Jenkins CI/CD + ECS Deployment Failure Workshop

> Automated incident investigation when Jenkins CI/CD pipeline deployments fail on Amazon ECS

This workshop demonstrates how **AWS DevOps Agent** automatically detects, investigates, and recommends remediation when a Jenkins-triggered deployment to Amazon ECS fails and triggers a rollback.

---

## Architecture

```
                    +-------------------+
                    |   Developer Push  |
                    +--------+----------+
                             |
                    +--------v----------+
                    |   Jenkins (EC2)   |
                    |  Build + Deploy   |
                    +--------+----------+
                             |
                    +--------v----------+
                    |    Amazon ECR     |
                    |  (Docker Images)  |
                    +--------+----------+
                             |
              +--------------v--------------+
              |      Amazon ECS Fargate     |
              |  +--------+  +--------+    |
              |  | Task 1 |  | Task 2 |    |
              |  +--------+  +--------+    |
              |     Circuit Breaker ON      |
              +--------------+--------------+
                             |
               Deployment Fails / Tasks Crash
                             |
         +-------------------v--------------------+
         |          EventBridge Rule              |
         | (SERVICE_DEPLOYMENT_FAILED / TaskStop) |
         +-------------------+--------------------+
                             |
              +--------------v--------------+
              |   CloudWatch Alarms (6)     |
              |   + SNS Notification        |
              +--------------+--------------+
                             |
              +--------------v--------------+
              |     AWS DevOps Agent        |
              |  - Reads ECS task logs      |
              |  - Correlates image change  |
              |  - Checks ALB health        |
              |  - Recommends rollback      |
              +-----------------------------+
```

## How It Works

1. **Jenkins builds and deploys** a Docker image to ECS Fargate via ECR
2. **Deployment fails** due to a container crash, health check failure, or resource exhaustion
3. **ECS Deployment Circuit Breaker** detects the failure and automatically rolls back
4. **EventBridge captures** the `SERVICE_DEPLOYMENT_FAILED` event
5. **CloudWatch Alarms fire** (unhealthy targets, low running count, high error rate)
6. **AWS DevOps Agent is triggered**, investigates the failure, and provides root cause analysis with remediation steps

## What's Included

| Component | Description |
|-----------|-------------|
| CloudFormation template | Full infrastructure: VPC, ALB, ECS Fargate, ECR, Jenkins EC2, CloudWatch, EventBridge |
| Flask application | Sample containerized app with health checks and API endpoints |
| Jenkins pipeline | Complete Jenkinsfile with build, test, push, deploy, and verify stages |
| 3 failure scenarios | Inject realistic deployment failures to trigger DevOps Agent |
| Deployment scripts | One-command deploy, cleanup, and validation |

## Failure Scenarios

### Scenario 1: Bad Docker Image (Container Crash)
Simulates a build that produces a fatally broken image. The container crashes immediately on startup due to a missing dependency (`ImportError`). ECS circuit breaker detects repeated task failures and rolls back.

**DevOps Agent findings:** Container crash logs showing `ModuleNotFoundError`, correlation with recent image change, recommendation to rollback.

### Scenario 2: Health Check Failure (Delayed Degradation)
Simulates an application that starts normally but becomes unhealthy after 30 seconds (e.g., a database connection pool exhausted). The ALB deregisters targets, ECS detects the failure pattern, and circuit breaker triggers rollback.

**DevOps Agent findings:** HTTP 503 from `/health` endpoint, error message "Database connection pool exhausted", pattern of initial success then degradation.

### Scenario 3: Resource Limits (OOM Kill)
Simulates a memory leak where the application gradually consumes all available memory. After passing initial health checks, the container is OOM-killed by the runtime (~90 seconds after start).

**DevOps Agent findings:** `OutOfMemoryError` in task stop reason, memory utilization spike to 100%, crash loop pattern in ECS events.

## Prerequisites

- AWS Account with admin or PowerUser access
- AWS CLI v2 configured (`aws configure`)
- Docker installed and running
- Bash shell (Linux/macOS, or WSL/Git Bash on Windows)
- ~$2-4/hour in AWS costs while running

## Quick Start

```bash
# Clone the repository
git clone https://github.com/hardikvijayshah/devops-agent-jenkins-ecs-workshop.git
cd devops-agent-jenkins-ecs-workshop

# Deploy everything (takes 10-15 minutes)
./scripts/deploy.sh devops-agent-jenkins your-email@example.com

# Inject a failure scenario
./scenarios/scenario1-bad-image/inject.sh

# Watch DevOps Agent investigate
# (Check CloudWatch Alarms and DevOps Agent console)

# Cleanup when done
./scripts/cleanup.sh devops-agent-jenkins
```

## Project Structure

```
jenkins-ecs-deployment-workshop/
|-- README.md                          # This file
|-- DEPLOYMENT_GUIDE.md                # Detailed step-by-step deployment instructions
|-- cloudformation/
|   +-- jenkins-ecs-workshop.yaml      # Full infrastructure template
|-- app/
|   |-- app.py                         # Flask application
|   |-- Dockerfile                     # Container image definition
|   +-- requirements.txt               # Python dependencies
|-- jenkins/
|   |-- Jenkinsfile                    # CI/CD pipeline definition
|   +-- jenkins-job-config.xml         # Jenkins job configuration
|-- scripts/
|   |-- deploy.sh                      # One-command deployment
|   |-- deploy-initial-image.sh        # Build and push initial image
|   |-- cleanup.sh                     # Full resource cleanup
|   +-- generate-traffic.sh            # Generate test traffic
|-- scenarios/
|   |-- scenario1-bad-image/
|   |   |-- inject.sh                  # Inject container crash failure
|   |   +-- rollback.sh               # Restore healthy state
|   |-- scenario2-health-check-fail/
|   |   |-- inject.sh                  # Inject health check degradation
|   |   +-- rollback.sh               # Restore healthy state
|   +-- scenario3-resource-limits/
|       |-- inject.sh                  # Inject memory leak / OOM
|       +-- rollback.sh               # Restore healthy state
+-- tests/
    +-- validate-stack.sh              # Post-deployment validation
```

## Infrastructure Details

### Resources Created

| Resource | Type | Details |
|----------|------|---------|
| VPC | Networking | 10.0.0.0/16 with 2 public subnets |
| ALB | Load Balancer | HTTP on port 80, health checks on /health:8080 |
| ECS Cluster | Container Orchestration | Fargate with Container Insights |
| ECS Service | Workload | 2 tasks, circuit breaker enabled |
| ECR Repository | Image Registry | Stores application Docker images |
| Jenkins EC2 | CI/CD Server | t3.medium with Docker + AWS CLI |
| CloudWatch Alarms | Monitoring | 6 alarms covering ECS, ALB, and deployment health |
| EventBridge Rules | Event Routing | Captures deployment failures and task stops |
| SNS Topics | Notifications | Deployment events and alarm notifications |

### CloudWatch Alarms

| Alarm | Trigger |
|-------|---------|
| `*-ecs-running-tasks` | Running tasks < desired count |
| `*-ecs-cpu-high` | CPU utilization > 80% for 5 minutes |
| `*-ecs-memory-high` | Memory utilization > 80% for 5 minutes |
| `*-alb-unhealthy` | Unhealthy target count > 0 for 3 minutes |
| `*-alb-5xx-errors` | 5xx error count > 10 in 5 minutes |
| `*-alb-response-time` | Response time > 5 seconds for 5 minutes |

### EventBridge Rules

| Rule | Event Pattern |
|------|--------------|
| ECS Deployment Failure | `detail.eventName == SERVICE_DEPLOYMENT_FAILED` |
| ECS Task Stopped | Task stops with `stopCode` in `[TaskFailedToStart, EssentialContainerExited]` |

## DevOps Agent Configuration

To connect AWS DevOps Agent to this workshop:

1. **Create a DevOps Agent Space** in the AWS Console
2. **Add the AWS account** where the workshop is deployed
3. **Configure resource tag filter**: `devopsagent=true`
4. **Enable alarm-based triggers** for the CloudWatch alarms
5. **Verify connectivity** by injecting a scenario and confirming the agent investigates

The stack tags all resources with `devopsagent=true` for easy filtering.

## Cost Estimate

| Resource | Approximate Cost |
|----------|-----------------|
| ECS Fargate (2 tasks, 0.25 vCPU, 512 MB) | ~$0.50/hour |
| EC2 t3.medium (Jenkins) | ~$0.04/hour |
| ALB | ~$0.02/hour |
| NAT Gateway | Not used (public subnets) |
| **Total** | **~$2-4/hour** |

Cleanup all resources immediately after the workshop to avoid charges.

## Troubleshooting

| Issue | Solution |
|-------|----------|
| Stack creation fails | Check IAM permissions include `iam:CreateRole`, `iam:CreateInstanceProfile` |
| ECS tasks not starting | Verify ECR image exists: `aws ecr list-images --repository-name devops-agent-jenkins-app` |
| Jenkins not accessible | Check security group allows your IP; wait 3-5 min for startup |
| ALB returns 503 | ECS tasks may be starting; wait 2-3 min or check target group health |
| Docker build fails locally | Ensure Docker daemon is running and you have disk space |

## Cleanup

```bash
# Remove all resources
./scripts/cleanup.sh devops-agent-jenkins
```

This deletes: ECR images, ECS service, CloudFormation stack (VPC, ALB, EC2, alarms, everything).

## License

This workshop is provided as-is for educational and demonstration purposes.
