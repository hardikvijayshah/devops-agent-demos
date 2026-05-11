# Lab 2: Step Functions Workflow Failure

## Scenario

A code deployment introduced a bug in the validate-order Lambda function. The function now tries to access a nested data path (`order['orderDetails']['itemList']['entries']`) that doesn't exist in the Step Functions input format. Every order validation fails with a `KeyError`, causing the entire order workflow to fail.

This simulates a real-world scenario where a code change breaks the contract between Step Functions and a Lambda task.

## What Gets Broken

The validate-order Lambda code is replaced with a version that has an incorrect data access pattern, causing `KeyError` on every invocation.

## Impact Chain

1. Every Step Functions execution fails at the `ValidateOrder` state
2. After retries (2 attempts), the execution catches the error and moves to `OrderFailed`
3. `OrderFailed` state publishes to EventBridge, routing to the DLQ
4. CloudWatch alarms fire: `sfn-failures`, `validate-order-errors`, `dlq-messages`

## Instructions

### Step 1: Inject the failure

```bash
./inject.sh devops-agent-serverless
```

### Step 2: Generate traffic

```bash
../../scripts/generate-traffic.sh devops-agent-serverless 15 2
```

Orders will be accepted by the API (200 OK) but fail during workflow processing.

### Step 3: Observe Step Functions failures

```bash
aws stepfunctions list-executions \
    --state-machine-arn $(aws cloudformation describe-stacks \
        --stack-name devops-agent-serverless \
        --query 'Stacks[0].Outputs[?OutputKey==`StateMachineArn`].OutputValue' \
        --output text) \
    --status-filter FAILED \
    --query 'executions[*].[name,status,stopDate]' \
    --output table
```

### Step 4: Trigger DevOps Agent investigation

Ask DevOps Agent: *"Why are Step Functions executions failing for the order workflow?"*

### Step 5: Review findings

Expected findings:
- **Root cause**: `KeyError: 'orderDetails'` in the validate-order Lambda
- **Evidence**: Step Functions execution history showing failure at `ValidateOrder` state
- **Correlation**: Lambda code change detected around the time failures began
- **Recommendation**: Fix the data access pattern in the validate-order function

### Step 6: Rollback

```bash
./rollback.sh devops-agent-serverless
```

## Key DevOps Agent Capabilities Demonstrated

- Step Functions execution history analysis
- Cross-service correlation (Step Functions → Lambda → CloudWatch Logs)
- Code change detection and deployment correlation
- Error pattern recognition across retry attempts
