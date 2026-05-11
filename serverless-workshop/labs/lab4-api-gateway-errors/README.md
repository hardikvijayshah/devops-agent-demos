# Lab 4: API Gateway 5xx Errors

## Scenario

A faulty code deployment to the order-api Lambda function introduces multiple response format bugs. The Lambda returns responses that don't conform to the API Gateway Lambda Proxy integration contract -- missing `statusCode`, non-string `body`, and unhandled exceptions.

This simulates a real-world scenario where a developer deploys code that works in unit tests but fails in the API Gateway integration context.

## What Gets Broken

The order-api Lambda code is replaced with a version that randomly produces three failure modes:
1. **Missing `statusCode`** in the response object -> 502 Bad Gateway
2. **Unhandled `RuntimeError` exception** -> 502 Bad Gateway
3. **Non-string `body` field** (dict instead of JSON string) -> 502 Bad Gateway

## Impact Chain

1. Every API request gets a 502 Bad Gateway response
2. No orders are written to DynamoDB
3. No Step Functions workflows are started
4. Client-visible error rate goes to ~100%
5. CloudWatch alarms fire: `api-5xx-errors`, `order-api-errors`

## Instructions

### Step 1: Inject the failure

```bash
./inject.sh devops-agent-serverless
```

### Step 2: Generate traffic

```bash
../../scripts/generate-traffic.sh devops-agent-serverless 30 1
```

All requests should return FAILED status.

### Step 3: Check API Gateway metrics

```bash
aws cloudwatch get-metric-statistics \
    --namespace AWS/ApiGateway \
    --metric-name 5XXError \
    --dimensions Name=ApiName,Value=devops-agent-serverless-api \
    --start-time $(date -u -d '5 minutes ago' +%Y-%m-%dT%H:%M:%S) \
    --end-time $(date -u +%Y-%m-%dT%H:%M:%S) \
    --period 60 \
    --statistics Sum
```

### Step 4: Trigger DevOps Agent investigation

Ask DevOps Agent: *"Our order API is returning 502 errors to all customers. What's wrong?"*

### Step 5: Review findings

Expected findings:
- **Root cause**: Lambda function returning malformed responses that don't match API Gateway proxy integration format
- **Evidence**: API Gateway execution logs showing integration errors, Lambda CloudWatch Logs showing exceptions
- **Correlation**: Code deployment timestamp matches error onset
- **Recommendation**: Fix Lambda response format to include `statusCode` (integer), `headers` (object), and `body` (JSON string)

### Step 6: Rollback

```bash
./rollback.sh devops-agent-serverless
```

## Key DevOps Agent Capabilities Demonstrated

- API Gateway error analysis (5xx vs 4xx patterns)
- Lambda integration error diagnosis
- Code deployment change detection
- API contract violation identification
