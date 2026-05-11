# Lab 3: DynamoDB Throttling Cascade

## Scenario

The inventory DynamoDB table's provisioned throughput has been drastically reduced to 1 RCU / 1 WCU. Under even moderate traffic, write operations to update inventory are throttled, causing cascading failures through the order workflow.

This simulates a real-world scenario where capacity planning is insufficient or a configuration change reduces throughput during peak hours.

## What Gets Broken

| Setting | Before | After |
|---------|--------|-------|
| Read Capacity | 5 RCU | 1 RCU |
| Write Capacity | 5 WCU | 1 WCU |

## Impact Chain

1. Inventory table throttles write requests (`ProvisionedThroughputExceededException`)
2. update-inventory Lambda fails with throttle errors
3. Step Functions retries the UpdateInventory task (2 attempts)
4. After exhausting retries, workflow moves to OrderFailed state
5. Failed orders pile up in the DLQ via EventBridge
6. CloudWatch alarms fire: `dynamodb-throttle`, `sfn-failures`, `dlq-messages`

## Instructions

### Step 1: Inject the failure

```bash
./inject.sh devops-agent-serverless
```

### Step 2: Generate heavy traffic

```bash
../../scripts/generate-traffic.sh devops-agent-serverless 50 0.5
```

Use a high request count with short intervals to maximize throttling.

### Step 3: Monitor throttling

```bash
aws cloudwatch get-metric-statistics \
    --namespace AWS/DynamoDB \
    --metric-name WriteThrottleEvents \
    --dimensions Name=TableName,Value=devops-agent-serverless-inventory \
    --start-time $(date -u -d '5 minutes ago' +%Y-%m-%dT%H:%M:%S) \
    --end-time $(date -u +%Y-%m-%dT%H:%M:%S) \
    --period 60 \
    --statistics Sum
```

### Step 4: Trigger DevOps Agent investigation

Ask DevOps Agent: *"Why are orders failing? I see DynamoDB throttling alarms."*

### Step 5: Review findings

Expected findings:
- **Root cause**: DynamoDB provisioned throughput too low for current traffic volume
- **Evidence**: WriteThrottleEvents metric spike, ConsumedWriteCapacityUnits exceeding provisioned
- **Correlation**: Throughput change timestamp matches throttling onset
- **Cascade**: Maps the full failure chain from DynamoDB → Lambda → Step Functions → DLQ
- **Recommendation**: Increase WCU or switch to on-demand billing mode

### Step 6: Rollback

```bash
./rollback.sh devops-agent-serverless
```

## Key DevOps Agent Capabilities Demonstrated

- DynamoDB capacity analysis and throttle detection
- Cascading failure chain mapping across services
- Metric correlation across DynamoDB, Lambda, and Step Functions
- Capacity planning recommendations
