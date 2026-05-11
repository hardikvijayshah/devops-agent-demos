# Lab 1: Lambda Timeout and Memory Constraint

## Scenario

The order-api Lambda function has been misconfigured with an extremely low timeout (1 second) and reduced memory (128MB). Under normal traffic, the function cannot complete its work -- writing to DynamoDB and starting the Step Functions execution -- before timing out.

This simulates a real-world scenario where a configuration change (perhaps from an IaC drift or an accidental deployment) degrades Lambda performance.

## What Gets Broken

| Setting | Before | After |
|---------|--------|-------|
| Timeout | 30 seconds | 1 second |
| Memory | 256 MB | 128 MB |

## Impact Chain

1. Order API Lambda times out on most requests
2. API Gateway returns 502/504 errors to clients
3. Orders are not written to DynamoDB
4. Step Functions workflows are never started
5. CloudWatch alarms fire: `order-api-errors`, `order-api-duration`, `api-5xx-errors`

## Instructions

### Step 1: Inject the failure

```bash
./inject.sh devops-agent-serverless
```

### Step 2: Generate traffic to trigger alarms

```bash
../../scripts/generate-traffic.sh devops-agent-serverless 30 1
```

You should see most requests returning FAILED status.

### Step 3: Wait for alarms

Wait 2-3 minutes for CloudWatch alarms to enter ALARM state. You can monitor them:

```bash
aws cloudwatch describe-alarms \
    --alarm-name-prefix devops-agent-serverless \
    --state-value ALARM \
    --query 'MetricAlarms[*].[AlarmName,StateValue]' \
    --output table
```

### Step 4: Trigger DevOps Agent investigation

In your DevOps Agent Space (web UI or Slack):
- Ask: *"Investigate why the order API is failing"*
- Or let the alarm-triggered webhook start an automatic investigation

### Step 5: Review DevOps Agent findings

Expected findings:
- **Root cause**: Lambda function timeout set to 1 second is insufficient for the operations performed (DynamoDB write + Step Functions start)
- **Evidence**: CloudWatch Logs showing `Task timed out after 1.00 seconds` errors
- **Correlation**: Configuration change timestamp matches the start of errors
- **Recommendation**: Increase timeout to at least 10-30 seconds and memory to 256MB+

### Step 6: Rollback

```bash
./rollback.sh devops-agent-serverless
```

## Key DevOps Agent Capabilities Demonstrated

- Lambda function error analysis via CloudWatch Logs Insights
- Configuration change detection
- Metric correlation (errors vs. duration vs. timeout setting)
- Root cause identification with actionable recommendations
