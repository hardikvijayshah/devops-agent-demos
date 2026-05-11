# Lab 5: EventBridge Rule Misconfiguration

## Scenario

The EventBridge rule for order completion notifications has been updated with incorrect event pattern matching. The rule now expects events from source `order.service.v2` with detail-type `OrderCompletedV2`, but the application still publishes events with `order.service` and `OrderCompleted`. No rules match, so completion notifications silently stop.

This simulates a real-world scenario where an EventBridge rule is updated during a migration but the event producer hasn't been updated yet, creating a silent failure.

## What Gets Broken

| Setting | Before | After |
|---------|--------|-------|
| Event source filter | `order.service` | `order.service.v2` |
| Detail-type filter | `OrderCompleted` | `OrderCompletedV2` |

## Impact Chain

1. Orders process successfully through the entire workflow
2. send-notification Lambda publishes `OrderCompleted` events to EventBridge
3. No rules match the published events (pattern mismatch)
4. SNS notification topic receives zero messages
5. Customer notifications stop silently -- no errors, no alarms initially
6. DLQ remains empty (events aren't failing, they're just unmatched)

## Why This Lab Is Interesting

This is a **silent failure** -- the hardest kind to detect. Orders complete successfully, all Lambda functions execute without errors, but downstream consumers never receive notifications. DevOps Agent must correlate the absence of expected behavior (no SNS publishes) with the EventBridge configuration change.

## Instructions

### Step 1: Inject the failure

```bash
./inject.sh devops-agent-serverless
```

### Step 2: Generate traffic

```bash
../../scripts/generate-traffic.sh devops-agent-serverless 15 2
```

All orders should succeed (200 OK responses).

### Step 3: Verify orders complete but notifications are missing

Check that Step Functions executions succeed:
```bash
aws stepfunctions list-executions \
    --state-machine-arn $(aws cloudformation describe-stacks \
        --stack-name devops-agent-serverless \
        --query 'Stacks[0].Outputs[?OutputKey==`StateMachineArn`].OutputValue' \
        --output text) \
    --status-filter SUCCEEDED \
    --max-results 5 \
    --query 'executions[*].[name,status]' \
    --output table
```

Check that SNS has zero recent publishes (no notifications sent).

### Step 4: Trigger DevOps Agent investigation

Ask DevOps Agent: *"Orders are completing but customers aren't receiving notifications. Can you investigate?"*

### Step 5: Review findings

Expected findings:
- **Root cause**: EventBridge rule pattern mismatch -- expects `order.service.v2` but events use `order.service`
- **Evidence**: EventBridge metrics showing events published but zero rule matches
- **Correlation**: Rule configuration change timestamp
- **Recommendation**: Update the rule pattern to match `order.service` / `OrderCompleted`, or update the producer to use the new event format

### Step 6: Rollback

```bash
./rollback.sh devops-agent-serverless
```

## Key DevOps Agent Capabilities Demonstrated

- Silent failure detection (absence of expected behavior)
- EventBridge rule analysis and pattern matching
- Configuration change correlation
- Cross-service event flow tracing (Lambda -> EventBridge -> SNS)
