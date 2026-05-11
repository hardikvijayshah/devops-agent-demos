# Lab 4: Post-Deployment Performance Regression

## Scenario

A new version (2.0.0) deploys successfully through the entire pipeline -- build passes, tests pass, deployment succeeds, health checks pass. However, the new code introduces artificial delays (3-5 seconds) on all non-health endpoints. The health endpoint is unaffected, so deployment validation passes, but real user traffic experiences severe latency.

This simulates a real-world scenario where a code change introduces a performance regression that unit tests don't catch (e.g., missing database index, inefficient query, accidental synchronous call).

## What Gets Broken

Application endpoints (`/`, `/api/status`, `/api/process`) have `time.sleep()` calls added (3-5 seconds). The `/health` endpoint remains fast, so all deployment checks pass.

## Impact Chain

1. Pipeline completes successfully (all stages pass)
2. Application deploys and health checks pass (health endpoint is fast)
3. Real user traffic hits slow endpoints
4. ALB TargetResponseTime increases dramatically (3-5 seconds)
5. CloudWatch alarms fire: `alb-latency` (after sustained high latency)
6. User-facing degradation with no pipeline-visible failure

## Why This Lab Is Interesting

This is the **most realistic and dangerous** failure mode -- everything in the pipeline says "success," but the application is degraded in production. It demonstrates the gap between CI/CD validation and production monitoring, and why DevOps Agent's ability to correlate deployments with metric changes is valuable.

## Instructions

### Step 1: Inject the failure

```bash
./inject.sh devops-agent-cicd
```

### Step 2: Wait for pipeline to complete

The pipeline will succeed fully (~8 minutes). Monitor:
```bash
watch -n 15 "aws codepipeline get-pipeline-state \
    --name devops-agent-cicd-pipeline \
    --query 'stageStates[*].{Stage:stageName,Status:latestExecution.status}' \
    --output table"
```

### Step 3: Generate traffic to trigger latency alarm

```bash
../../scripts/generate-traffic.sh devops-agent-cicd 30 1
```

You'll notice requests taking 3-5 seconds each.

### Step 4: Trigger DevOps Agent investigation

Ask DevOps Agent: *"Our application latency spiked after the latest deployment. All pipeline stages passed. What's causing the slowdown?"*

### Step 5: Review findings

Expected findings:
- **Root cause**: Code change in version 2.0.0 introduced `time.sleep()` delays in request handlers
- **Evidence**: ALB TargetResponseTime metric spike, correlated with CodeDeploy deployment timestamp
- **Correlation**: Deployment of version 2.0.0 matches the exact time latency increased
- **Recommendation**: Rollback to previous version or fix the performance regression in the code

### Step 6: Rollback

```bash
./rollback.sh devops-agent-cicd
```

## Key DevOps Agent Capabilities Demonstrated

- Post-deployment metric correlation
- Deployment-to-metric-change timeline analysis
- Performance regression detection (latency spike identification)
- Root cause analysis spanning CI/CD and runtime monitoring
