# Lab 2: Capacity Planning Gaps

## Scenario

The infrastructure uses **fixed provisioned capacity with no auto-scaling**. DynamoDB tables have low WCU/RCU limits, Lambda functions have no reserved concurrency, and the Auto Scaling Group has Min=Max=2 (cannot scale). Under burst traffic, the system will throttle and degrade.

DevOps Agent's Evaluation mode identifies these capacity risks proactively.

## What DevOps Agent Should Discover

### DynamoDB Capacity Issues
| Table | Provisioned | Gap | Risk |
|-------|------------|-----|------|
| Orders | 5 WCU / 5 RCU | No auto-scaling | Throttling under burst |
| Inventory | 3 WCU / 3 RCU | No auto-scaling | Throttling on updates |
| Orders GSI | 2 WCU / 2 RCU | Bottleneck | GSI falls behind |
| Sessions | 10 WCU / 10 RCU | No auto-scaling | TTL cleanup + writes compete |

### Lambda Capacity Issues
| Function | Memory | Gap | Risk |
|----------|--------|-----|------|
| order-processor | 128MB | No reserved concurrency | Throttled by other functions |
| inventory-checker | 128MB | No reserved concurrency | Competes for pool |
| session-cleanup | 128MB | 900s timeout | Long-running scan blocks concurrency |

### Auto Scaling Issues
| Setting | Current | Gap |
|---------|---------|-----|
| MinSize | 2 | Cannot scale down during low traffic |
| MaxSize | 2 | Cannot scale out under load |
| Scaling Policy | None | No automatic response to CPU/request changes |
| Scheduled Actions | None | No pre-scaling for known peaks |

## Steps

```bash
# 1. Generate burst traffic to demonstrate capacity pressure
./inject.sh [stack-name]

# 2. Wait 5 minutes for metrics

# 3. Trigger DevOps Agent Evaluation
aws devops-agent create-backlog-task \
    --agent-space-id <your-space-id> \
    --task-type EVALUATION \
    --title "Evaluate capacity planning and auto-scaling for devops-eval" \
    --priority HIGH

# 4. Review recommendations
aws devops-agent list-recommendations \
    --agent-space-id <your-space-id> \
    --status PROPOSED
```

## Expected Evaluation Output

1. **"Enable DynamoDB auto-scaling or switch to on-demand"** (HIGH)
   - ConsumedWriteCapacityUnits approaching provisioned limit
   - Agent-ready spec: Application Auto Scaling target + policy configuration

2. **"Add target tracking scaling policy to ASG"** (HIGH)
   - Fixed capacity cannot respond to load changes
   - Agent-ready spec: Target tracking policy on ALBRequestCountPerTarget

3. **"Set reserved concurrency for order-processor"** (MEDIUM)
   - Critical path function sharing unreserved concurrency pool
   - Agent-ready spec: Lambda reserved concurrency setting

4. **"Reduce Lambda timeout from 300s to 30s"** (MEDIUM)
   - Generous timeout masks hung invocations, consuming concurrency
   - Agent-ready spec: Updated function configuration

## Difficulty

**Intermediate** -- Requires understanding of AWS capacity concepts and auto-scaling patterns.

## Duration

- Inject: ~3 minutes (burst traffic)
- Wait: 5 minutes (metric aggregation)
- Evaluation: 5-10 minutes
- Total: ~18 minutes
