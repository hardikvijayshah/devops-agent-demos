# Lab 3: Deployment Health Check Failure

## Scenario

A deployment configuration change references a broken start script that launches the application on the wrong port (8080 instead of 5000). The application starts successfully on the instance, but the ALB health check targets port 5000, so instances are marked unhealthy. CodeDeploy detects the health check failure and triggers an automatic rollback.

## What Gets Broken

- `appspec.yml` references `start_server_broken.sh` instead of `start_server.sh`
- The broken script starts gunicorn on port 8080 instead of port 5000
- ALB Target Group health check on port 5000 fails -> instances marked unhealthy

## Impact Chain

1. Source and Build stages succeed
2. Test stage succeeds (unit tests don't check deployment config)
3. CodeDeploy begins deployment to EC2 instances
4. Application starts on port 8080 (wrong port)
5. CodeDeploy `ValidateService` passes (checks localhost:8080)
6. ALB health check on port 5000 fails -> instances go unhealthy
7. CodeDeploy alarm-based rollback triggers
8. CloudWatch alarms fire: `alb-unhealthy`, `deploy-failures`

## Why This Lab Is Interesting

This is a **deployment-environment mismatch** -- the application works perfectly on the instance, and even passes the CodeDeploy validation check, but fails the ALB health check because of a port mismatch. It demonstrates the gap between "application runs" and "application is properly integrated."

## Instructions

### Step 1: Inject the failure

```bash
./inject.sh devops-agent-cicd
```

### Step 2: Monitor deployment

```bash
DEPLOY_APP=$(aws cloudformation describe-stacks \
    --stack-name devops-agent-cicd \
    --query 'Stacks[0].Outputs[?OutputKey==`CodeDeployApplicationName`].OutputValue' \
    --output text)

aws deploy list-deployments \
    --application-name "${DEPLOY_APP}" \
    --deployment-group-name devops-agent-cicd-dg \
    --query 'deployments[0]' --output text | \
xargs -I{} aws deploy get-deployment --deployment-id {} \
    --query 'deploymentInfo.{Status:status,ErrorInfo:errorInformation}' \
    --output table
```

### Step 3: Check ALB target health

```bash
aws elbv2 describe-target-health \
    --target-group-arn $(aws elbv2 describe-target-groups \
        --names devops-agent-cicd-tg \
        --query 'TargetGroups[0].TargetGroupArn' --output text) \
    --query 'TargetHealthDescriptions[*].{Target:Target.Id,Health:TargetHealth.State,Reason:TargetHealth.Reason}' \
    --output table
```

### Step 4: Trigger DevOps Agent investigation

Ask DevOps Agent: *"CodeDeploy deployment failed and rolled back. ALB shows unhealthy targets. What happened?"*

### Step 5: Review findings

Expected findings:
- **Root cause**: Application listening on port 8080 but ALB health check expects port 5000
- **Evidence**: ALB target health showing "unhealthy" with reason "connection refused on port 5000", CodeDeploy deployment events
- **Correlation**: Deployment configuration change (appspec.yml referencing wrong start script)
- **Recommendation**: Fix the start script to use port 5000, or update the ALB target group health check port

### Step 6: Rollback

```bash
./rollback.sh devops-agent-cicd
```

## Key DevOps Agent Capabilities Demonstrated

- CodeDeploy deployment event analysis
- ALB health check correlation with deployment
- Port/configuration mismatch detection
- Multi-layer failure analysis (CodeDeploy -> ALB -> EC2)
