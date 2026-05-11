# Lab 3: Application Resilience Weaknesses

## Scenario

The Lambda functions have **no resilience patterns** -- no retry logic, no dead letter queues, no input validation, no circuit breakers. Under real-world conditions (transient failures, malformed input, throttling), requests fail permanently instead of being retried or gracefully degraded.

DevOps Agent evaluates the application code and configuration to identify these weaknesses.

## What DevOps Agent Should Discover

### Missing Resilience Patterns
| Gap | Impact | Evidence |
|-----|--------|----------|
| No input validation | 500 errors on malformed requests | KeyError/TypeError in logs |
| No retry logic | Throttled DynamoDB writes fail permanently | No retry config, errors in logs |
| No DLQ | Failed invocations lost forever | DeadLetterConfig is null |
| No circuit breaker | Cascading failures to downstream services | All errors propagate |
| No error handling | Unhandled exceptions expose internals | Stack traces in responses |

### Inefficient Patterns
| Pattern | Location | Recommendation |
|---------|----------|----------------|
| Full table scan | inventory-checker | Use Query with key condition |
| Scan in order-processor | Inventory lookup | GetItem by productId (direct key lookup) |
| Sequential deletes | session-cleanup | BatchWriteItem (25 items/batch) |
| No pagination | All scan operations | Handle LastEvaluatedKey |
| Redundant cleanup | session-cleanup | TTL already handles expiration |

### Configuration Issues
| Setting | Current | Recommended |
|---------|---------|-------------|
| DLQ | Not configured | SQS queue per function |
| Reserved Concurrency | None | 50-100 for order-processor |
| X-Ray Tracing | Disabled | Active (trace DynamoDB calls) |
| Timeout (order-processor) | 300s | 30s (fail fast) |
| Timeout (session-cleanup) | 900s | 120s (with pagination) |

## Steps

```bash
# 1. Generate requests that expose resilience gaps
./inject.sh [stack-name]

# 2. Wait 3-5 minutes for logs and metrics

# 3. Trigger DevOps Agent Evaluation
aws devops-agent create-backlog-task \
    --agent-space-id <your-space-id> \
    --task-type EVALUATION \
    --title "Evaluate application resilience patterns for Lambda functions" \
    --priority HIGH

# 4. Review recommendations
aws devops-agent list-recommendations \
    --agent-space-id <your-space-id> \
    --status PROPOSED
```

## Expected Evaluation Output

1. **"Add DLQ to order-processor Lambda"** (HIGH)
   - Failed invocations are permanently lost
   - Agent-ready spec: SQS DLQ creation + Lambda DLQ configuration

2. **"Add input validation to order-processor"** (HIGH)
   - Missing fields cause unhandled KeyError (500 responses)
   - Agent-ready spec: Validation logic for required fields and types

3. **"Replace table scan with GetItem in order-processor"** (MEDIUM)
   - Current inventory lookup uses Scan with FilterExpression
   - Agent-ready spec: Refactored code using GetItem(productId)

4. **"Add retry with exponential backoff for DynamoDB operations"** (MEDIUM)
   - ProvisionedThroughputExceededException causes permanent failure
   - Agent-ready spec: boto3 retry configuration or custom backoff

5. **"Remove redundant session-cleanup function"** (LOW)
   - DynamoDB TTL already handles session expiration
   - The cleanup function duplicates TTL behavior with worse performance

## Difficulty

**Intermediate** -- Requires understanding of resilience patterns and Lambda best practices.

## Duration

- Inject: ~3 minutes
- Wait: 5 minutes
- Evaluation: 5-10 minutes
- Total: ~18 minutes
