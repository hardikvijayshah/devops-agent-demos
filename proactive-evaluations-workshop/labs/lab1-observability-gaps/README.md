# Lab 1: Observability Gaps

## Scenario

The infrastructure is deployed with **intentionally incomplete monitoring**. Only 3 CloudWatch alarms exist where 10+ should be configured. Existing alarm thresholds are too lenient to catch real incidents early. No X-Ray tracing, no metric filters, no operational dashboard.

DevOps Agent's **Evaluation mode** analyzes the infrastructure and identifies these gaps proactively -- before any incident occurs.

## What DevOps Agent Should Discover

### Missing Alarms
| Resource | Missing Metric | Why It Matters |
|----------|---------------|----------------|
| DynamoDB Orders | ConsumedWriteCapacityUnits | Won't detect approaching capacity limits |
| DynamoDB Orders | ThrottledRequests | Won't detect active throttling |
| Lambda order-processor | Duration | Won't detect timeout-approaching functions |
| Lambda order-processor | ConcurrentExecutions | Won't detect concurrency exhaustion |
| Lambda order-processor | Throttles | Won't detect invocation throttling |
| ALB | TargetResponseTime | Won't detect latency degradation |
| ALB | RequestCount | Won't detect traffic anomalies |
| API Gateway | Latency | Won't detect API response time issues |

### Lenient Thresholds
| Alarm | Current | Recommended | Impact |
|-------|---------|-------------|--------|
| Lambda errors | >= 50 in 3x5min | >= 3 in 2x1min | 15+ minutes of errors before alerting |
| ALB unhealthy | >= 2 in 3x5min | >= 1 in 2x1min | Both hosts must fail for 15 minutes |
| API 5xx | >= 100 in 3x5min | >= 5 in 2x1min | 100 customer errors before any alert |

### Missing Capabilities
- No X-Ray tracing (cannot trace requests across Lambda + DynamoDB)
- No CloudWatch metric filters (cannot alert on specific log patterns)
- No CloudWatch dashboard (no operational visibility)

## Steps

```bash
# 1. Generate traffic to populate metrics
./inject.sh [stack-name]

# 2. Wait 5 minutes for metrics to aggregate

# 3. Trigger DevOps Agent Evaluation
#    Via console: Create evaluation task targeting observability
#    Via CLI:
aws devops-agent create-backlog-task \
    --agent-space-id <your-space-id> \
    --task-type EVALUATION \
    --title "Evaluate observability posture for devops-eval resources" \
    --priority HIGH

# 4. Review recommendations in Ops Backlog
aws devops-agent list-recommendations \
    --agent-space-id <your-space-id> \
    --status PROPOSED
```

## Expected Evaluation Output

DevOps Agent should produce recommendations like:

1. **"Add DynamoDB throttle alarm"** (HIGH priority)
   - ConsumedWriteCapacityUnits approaching provisioned limit with no alarm
   - Agent-ready spec: CloudFormation snippet for the missing alarm

2. **"Tighten Lambda error alarm threshold"** (HIGH priority)
   - Current threshold (50 errors) allows significant customer impact
   - Recommends: >= 3 errors in 2 evaluation periods of 60 seconds

3. **"Enable X-Ray tracing"** (MEDIUM priority)
   - No distributed tracing configured
   - Cannot trace request path across API Gateway -> Lambda -> DynamoDB

4. **"Add API Gateway latency alarm"** (MEDIUM priority)
   - No monitoring of response time degradation

## Difficulty

**Beginner** -- No infrastructure changes needed. DevOps Agent analyzes existing state.

## Duration

- Inject: ~2 minutes (traffic generation)
- Wait: 5 minutes (metric aggregation)
- Evaluation: 3-8 minutes (agent processing)
- Total: ~15 minutes
