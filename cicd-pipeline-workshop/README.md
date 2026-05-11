# AWS DevOps Agent - CI/CD Pipeline Failure Investigation Workshop

Hands-on workshop demonstrating AWS DevOps Agent's autonomous investigation capabilities across a full CI/CD deployment pipeline. Five labs inject realistic failures at every pipeline stage -- build, test, deploy, post-deploy, and IAM permissions -- then showcase how DevOps Agent correlates CodePipeline events, CodeBuild logs, CodeDeploy health checks, ALB metrics, and CloudTrail to identify root causes.

---

## Architecture

### Pipeline Overview

```
+------------------+     +------------------+     +------------------+     +------------------+
|     SOURCE       |     |      BUILD       |     |      TEST        |     |     DEPLOY       |
|                  |     |                  |     |                  |     |                  |
|  S3 Bucket       |---->|  CodeBuild       |---->|  CodeBuild       |---->|  CodeDeploy      |
|  source/app.zip  |     |  python:3.12     |     |  unittest suite  |     |  AllAtOnce       |
|  (versioned)     |     |  pip install     |     |  4 test cases    |     |  auto-rollback   |
|                  |     |  py_compile      |     |                  |     |                  |
+------------------+     +------------------+     +------------------+     +--------+---------+
                                                                                   |
                         +------ CodeDeploy Lifecycle ------+                       |
                         |                                  |                       |
                         |  AfterInstall:                   |              +--------v---------+
                         |    install_dependencies.sh       |              |  Auto Scaling    |
                         |    (pip install requirements)    |              |  Group           |
                         |                                  |              |                  |
                         |  ApplicationStart:               |              |  2x t3.micro     |
                         |    start_server.sh               |              |  Amazon Linux    |
                         |    (gunicorn on port 5000)       |              |  2023            |
                         |                                  |              |  CodeDeploy agent|
                         |  ValidateService:                |              +--------+---------+
                         |    validate_service.sh           |                       |
                         |    (curl /health, 10 retries)    |              +--------v---------+
                         +----------------------------------+              |       ALB        |
                                                                          |                  |
                                                                          |  Port 80 -> 5000 |
                                                                          |  Health: /health  |
                                                                          |  Interval: 15s   |
                                                                          |  Threshold: 2/3  |
                                                                          +------------------+
```

### Network Architecture

```
VPC: 10.0.0.0/16
|
+-- Internet Gateway
|
+-- Public Route Table (0.0.0.0/0 -> IGW)
|
+-- Public Subnet 1: 10.0.1.0/24 (AZ-a)
|   +-- EC2 Instance (t3.micro, Auto Scaling Group)
|   +-- ALB (internet-facing)
|
+-- Public Subnet 2: 10.0.2.0/24 (AZ-b)
    +-- EC2 Instance (t3.micro, Auto Scaling Group)

Security Groups:
  ALB SG:  Inbound TCP 80 from 0.0.0.0/0
  EC2 SG:  Inbound TCP 5000 from ALB SG only
```

### Application

Flask web application served by gunicorn (2 workers, port 5000):

| Endpoint | Method | Response | Purpose |
|----------|--------|----------|---------|
| `/health` | GET | `{"status": "healthy", "uptime": ..., "hostname": ..., "version": ...}` | ALB health check + instance identification |
| `/` | GET | `{"service": "DevOps Agent CI/CD Workshop", "version": ..., "hostname": ...}` | Service info |
| `/api/status` | GET | `{"status": "operational", "uptime": ..., "version": ...}` | Operational status |
| `/api/process` | POST | `{"processed": true, "input": ..., "hostname": ...}` | Data processing (accepts JSON body) |

### Monitoring

```
CloudWatch Alarms (8):
+--------------------+    +-------------------+    +--------------------+
| Pipeline Alarms    |    | Application Alarms|    | Infrastructure     |
|                    |    |                   |    | Alarms             |
| - build-failures   |    | - alb-unhealthy   |    | - cpu-utilization  |
| - test-failures    |    | - alb-5xx         |    | - deploy-failures  |
| - pipeline-failures|    | - alb-latency     |    |                    |
+--------------------+    +-------------------+    +--------------------+
         |                         |                        |
         +------------+------------+------------------------+
                      |
               SNS Alarm Topic  -----> (optional) Email subscription
                      |
               SNS Pipeline Topic ----> CodeStar Notification Rule
                                        (pipeline success/failure events)
```

---

## CloudFormation Resources (39 total)

| Category | Resource | Type | Purpose |
|----------|----------|------|---------|
| **VPC** | VPC | `AWS::EC2::VPC` | 10.0.0.0/16 CIDR with DNS support |
| | InternetGateway | `AWS::EC2::InternetGateway` | Internet access for public subnets |
| | VPCGatewayAttachment | `AWS::EC2::VPCGatewayAttachment` | Attaches IGW to VPC |
| | PublicSubnet1 | `AWS::EC2::Subnet` | 10.0.1.0/24 in AZ-a |
| | PublicSubnet2 | `AWS::EC2::Subnet` | 10.0.2.0/24 in AZ-b |
| | PublicRouteTable | `AWS::EC2::RouteTable` | Routes for public subnets |
| | PublicRoute | `AWS::EC2::Route` | 0.0.0.0/0 -> IGW |
| **Security** | ALBSecurityGroup | `AWS::EC2::SecurityGroup` | ALB: inbound TCP 80 |
| | EC2SecurityGroup | `AWS::EC2::SecurityGroup` | EC2: inbound TCP 5000 from ALB SG |
| **Load Balancer** | ALB | `AWS::ElasticLoadBalancingV2::LoadBalancer` | Internet-facing application LB |
| | ALBTargetGroup | `AWS::ElasticLoadBalancingV2::TargetGroup` | Health check on /health, port 5000 |
| | ALBListener | `AWS::ElasticLoadBalancingV2::Listener` | HTTP:80 forward to target group |
| **Compute** | LaunchTemplate | `AWS::EC2::LaunchTemplate` | AL2023, CodeDeploy agent install via UserData |
| | AutoScalingGroup | `AWS::AutoScaling::AutoScalingGroup` | Min:2, Max:4, Desired:2, ELB health check |
| **CI/CD** | ArtifactBucket | `AWS::S3::Bucket` | Versioned, 7-day lifecycle on old versions |
| | BuildProject | `AWS::CodeBuild::Project` | Build stage (amazonlinux2, python 3.12) |
| | TestProject | `AWS::CodeBuild::Project` | Test stage (unittest execution) |
| | CodeDeployApplication | `AWS::CodeDeploy::Application` | Server compute platform |
| | DeploymentGroup | `AWS::CodeDeploy::DeploymentGroup` | Targets ASG, auto-rollback on failure/alarm |
| | Pipeline | `AWS::CodePipeline::Pipeline` | 4 stages: Source -> Build -> Test -> Deploy |
| **IAM** | EC2InstanceRole + Profile | `AWS::IAM::Role` | SSM access + S3 artifact download |
| | CodeBuildRole | `AWS::IAM::Role` | CloudWatch Logs + S3 artifact access |
| | CodeDeployRole | `AWS::IAM::Role` | AWSCodeDeployRole managed policy |
| | CodePipelineRole | `AWS::IAM::Role` | S3 + CodeBuild + CodeDeploy orchestration |
| | SourcePackagerRole | `AWS::IAM::Role` | Lambda role for custom resource |
| **Lambda** | SourcePackagerFunction | `AWS::Lambda::Function` | Custom resource: packages and uploads app.zip |
| **SNS** | AlarmNotificationTopic | `AWS::SNS::Topic` | Alarm notifications |
| | PipelineNotificationTopic | `AWS::SNS::Topic` | Pipeline event notifications |
| **Notifications** | PipelineNotificationRule | `AWS::CodeStarNotifications::NotificationRule` | Pipeline success/failure events |
| **Alarms** | 8x CloudWatch Alarms | `AWS::CloudWatch::Alarm` | See alarm details below |

### CloudWatch Alarms

| Alarm Name | Metric Namespace | Metric | Threshold | Period | Eval |
|-----------|-----------------|--------|-----------|--------|------|
| `{prefix}-build-failures` | AWS/CodeBuild | FailedBuilds | >= 1 | 5 min | 1 |
| `{prefix}-test-failures` | AWS/CodeBuild | FailedBuilds | >= 1 | 5 min | 1 |
| `{prefix}-pipeline-failures` | AWS/CodePipeline | PipelineExecutionFailure | >= 1 | 5 min | 1 |
| `{prefix}-deploy-failures` | AWS/CodeDeploy | DeploymentFailure | >= 1 | 5 min | 1 |
| `{prefix}-alb-unhealthy` | AWS/ApplicationELB | UnHealthyHostCount | >= 1 avg | 60s | 2 |
| `{prefix}-alb-5xx` | AWS/ApplicationELB | HTTPCode_Target_5XX_Count | >= 10 sum | 60s | 2 |
| `{prefix}-alb-latency` | AWS/ApplicationELB | TargetResponseTime | >= 3s avg | 60s | 3 |
| `{prefix}-cpu-utilization` | AWS/EC2 | CPUUtilization | >= 80% avg | 60s | 3 |

### CodeDeploy Auto-Rollback

The deployment group is configured with automatic rollback on:
- `DEPLOYMENT_FAILURE` -- any deployment lifecycle event fails
- `DEPLOYMENT_STOP_ON_ALARM` -- the `alb-unhealthy` alarm enters ALARM state

---

## Prerequisites

| Requirement | Details |
|-------------|---------|
| **AWS CLI v2** | Configured with `aws configure` |
| **Permissions** | IAM, VPC, EC2, ALB, CodePipeline, CodeBuild, CodeDeploy, S3, SNS, CloudWatch, CloudFormation, CodeStar Notifications |
| **DevOps Agent** | Agent Space configured with tag discovery (`devopsagent = true`) |
| **Utilities** | `bash`, `curl`, `zip` |
| **Region** | `us-east-1` recommended (default) |

---

## Deployment

```bash
# Default deployment
./scripts/deploy.sh

# Custom stack name + alarm email
./scripts/deploy.sh my-cicd-workshop user@example.com

# Specific region
export AWS_REGION=us-west-2
./scripts/deploy.sh
```

**Deployment time:** ~10-15 minutes (includes EC2 provisioning, CodeDeploy agent install, initial pipeline run)
**Estimated cost:** ~$2-3/hour (EC2 instances and ALB are the primary cost drivers)

### What the Deploy Script Does

1. Validates the CloudFormation template syntax
2. Deploys the stack with `CAPABILITY_NAMED_IAM`
3. Tags all resources with `devopsagent=true`
4. Prints all stack outputs (ALB endpoint, pipeline name, CodeBuild/CodeDeploy names)
5. Waits for EC2 instances to pass ALB health checks
6. Triggers the initial pipeline execution
7. Custom resource Lambda packages the Flask app and uploads `source/app.zip` to S3

### Validate Deployment

```bash
./tests/validate-stack.sh [stack-name]
```

This checks: stack status, VPC, ALB endpoint, ASG instance count, CodePipeline status, CodeBuild projects, CodeDeploy application/group, S3 source artifact, CloudWatch alarms, and runs an end-to-end ALB health check.

---

## Labs

| Lab | Scenario | What Gets Changed | Pipeline Result | Alarms Triggered | Difficulty |
|-----|----------|-------------------|----------------|-----------------|-----------|
| **1** | [Build Failure](labs/lab1-build-failure/) | `nonexistent-package-xyz` added to requirements.txt | Build FAILS | build-failures, pipeline-failures | Beginner |
| **2** | [Test Failure](labs/lab2-test-failure/) | App code breaks API contract (2 regression bugs) | Build OK, Test FAILS | test-failures, pipeline-failures | Beginner |
| **3** | [Deploy Health Check](labs/lab3-deploy-health-check/) | Start script uses port 8080 instead of 5000 | Build OK, Test OK, Deploy FAILS (rollback) | alb-unhealthy, deploy-failures | Intermediate |
| **4** | [Post-Deploy Regression](labs/lab4-post-deploy-regression/) | `time.sleep(3-5s)` added to all endpoints | All stages PASS, app degraded | alb-latency | Advanced |
| **5** | [Pipeline Permission](labs/lab5-pipeline-permission/) | Explicit S3 Deny added to CodeBuild IAM role | Build FAILS (AccessDenied) | build-failures, pipeline-failures | Advanced |

### Recommended Lab Order

1. **Lab 1** (Build Failure) -- simplest scenario, fastest feedback (~2 min to failure)
2. **Lab 2** (Test Failure) -- builds on Lab 1, introduces multi-stage analysis
3. **Lab 5** (Pipeline Permission) -- IAM-focused, demonstrates CloudTrail correlation
4. **Lab 3** (Deploy Health Check) -- requires full pipeline run + ALB monitoring
5. **Lab 4** (Post-Deploy Regression) -- most complex, all stages pass, requires traffic generation

### Lab Flow

```bash
# 1. Navigate to the lab
cd labs/lab1-build-failure/

# 2. Inject the failure
./inject.sh [stack-name]

# 3. Monitor pipeline (build/test labs: failure appears in 2-5 min)
aws codepipeline get-pipeline-state \
    --name [stack-name]-pipeline \
    --query 'stageStates[*].{Stage:stageName,Status:latestExecution.status}' \
    --output table

# 4. For Labs 3-4: generate traffic after deployment
../../scripts/generate-traffic.sh [stack-name] 30 1

# 5. Investigate with DevOps Agent
# Via web UI, Slack, or automatic webhook

# 6. Rollback when done
./rollback.sh [stack-name]
```

### Lab Details

**Lab 1 -- Build Failure (Beginner):**
Adds `nonexistent-package-xyz==99.99.99` to `requirements.txt`. The CodeBuild install phase fails with `pip: ERROR: Could not find a version that satisfies the requirement`. Pipeline stops at Build stage. DevOps Agent should identify the CodeBuild failure, find the pip error in build logs, and correlate with the source artifact change.

**Lab 2 -- Test Failure (Beginner):**
Deploys app code with two regression bugs: `/api/status` returns `'degraded'` instead of `'operational'`, and `/api/process` drops the `'processed'` field. Build passes (code compiles), but Test stage catches both regressions via unittest assertions. DevOps Agent should analyze CodeBuild test logs, identify the exact failing assertions, and link to the code change.

**Lab 3 -- Deploy Health Check Failure (Intermediate):**
Modifies `appspec.yml` to reference `start_server_broken.sh`, which starts gunicorn on port 8080 instead of 5000. Build passes, tests pass, CodeDeploy `ValidateService` even passes (checks localhost:8080). But the ALB health check on port 5000 fails, marking instances unhealthy. CodeDeploy auto-rollback triggers. DevOps Agent should identify the port mismatch between the application (8080) and the ALB target group (5000).

**Lab 4 -- Post-Deploy Performance Regression (Advanced):**
The most realistic and dangerous scenario. Deploys code with `time.sleep()` calls (3-5 seconds) on all endpoints except `/health`. Pipeline completes successfully. Health checks pass. But real traffic experiences severe latency. DevOps Agent must correlate the deployment timestamp with the ALB `TargetResponseTime` metric spike -- there are no errors, only performance degradation.

**Lab 5 -- Pipeline Permission Issue (Advanced):**
Replaces the CodeBuild IAM role's inline policy with one that includes an explicit `Deny` on S3 actions. CodeBuild can still write logs but cannot download source artifacts or upload build output. The error is a generic `AccessDenied`. DevOps Agent must correlate the IAM policy change (visible in CloudTrail) with the CodeBuild failure, crossing the service boundary between IAM and CodeBuild.

---

## DevOps Agent Space Configuration

After deploying the stack:

1. **Tag-based discovery:** Configure Agent Space to discover resources with tag `devopsagent = true`
2. **CloudWatch Metrics:** Ensure access to CodeBuild, CodePipeline, CodeDeploy, ApplicationELB, and EC2 namespaces
3. **CloudWatch Logs:** Ensure access to `/aws/codebuild/{prefix}-build` and `/aws/codebuild/{prefix}-test` log groups
4. **CloudTrail:** Enable for IAM policy changes (`PutRolePolicy`), CodePipeline executions, and CodeDeploy deployments
5. **CodePipeline integration:** Connect DevOps Agent to monitor pipeline state change events

---

## Cost Breakdown

| Service | Cost Driver | Estimate |
|---------|------------|----------|
| EC2 | 2x t3.micro (on-demand) | ~$1.04/hr |
| ALB | Load balancer hour + LCU | ~$0.50/hr |
| CodeBuild | Build minutes (general1.small, ~$0.005/min) | ~$0.01/build |
| S3 | Artifact storage (versioned) | ~$0.01/hr |
| CloudWatch | 8 alarms + log storage | ~$0.10/hr |
| **Total** | | **~$2-3/hr** |

---

## Cleanup

```bash
./scripts/cleanup.sh [stack-name]
```

This script:
1. Prompts for confirmation
2. Empties the S3 artifact bucket (all versions and delete markers)
3. Deletes the CloudFormation stack
4. Waits for stack deletion to complete

---

## Troubleshooting

| Problem | Solution |
|---------|----------|
| EC2 instances not registering with ALB | Wait 5 min for boot + CodeDeploy agent; check EC2 SG allows port 5000 from ALB SG |
| Pipeline not starting | Verify `source/app.zip` in S3; custom resource should create it on stack deploy |
| CodeDeploy agent not running | SSM Session Manager: `sudo systemctl status codedeploy-agent` |
| First pipeline run fails | EC2 instances may not be ready; wait for ALB healthy, retry pipeline |
| Build fails with AccessDenied (not Lab 5) | Check CodeBuild role has S3 permissions; verify artifact bucket name matches |
| Deploy rolls back immediately | Check ALB target health; verify start script uses port 5000; check /health endpoint |
| Rollback doesn't restore clean state | Labs 2-4 rollback delegates to Lab 1's rollback (uploads original source); Lab 5 restores IAM policy directly |
| Alarms stay in ALARM after rollback | Wait 1-2 evaluation periods for healthy metrics; run traffic to generate healthy data points |
| Stack deletion fails (bucket not empty) | The cleanup script handles this; if manual deletion, empty bucket first: `aws s3 rm s3://[bucket] --recursive` |
