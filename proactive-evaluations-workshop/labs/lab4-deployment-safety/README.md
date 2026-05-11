# Lab 4: Deployment Safety Gaps

## Scenario

Lambda functions are deployed with **no safety mechanisms** -- no versioning, no aliases, no CodeDeploy integration, no canary/linear traffic shifting, and no deployment alarms. A bad deployment goes to 100% of traffic instantly with no way to automatically rollback.

This lab deploys intentionally broken code to demonstrate the risk, then DevOps Agent evaluates the deployment posture and recommends safety improvements.

## What DevOps Agent Should Discover

### Missing Deployment Safeguards
| Safeguard | Status | Risk |
|-----------|--------|------|
| Lambda versioning | Not used | Cannot reference specific code versions |
| Lambda aliases (prod/staging) | Not configured | No stable reference for traffic routing |
| CodeDeploy for Lambda | Not configured | No progressive/canary deployment |
| Traffic shifting | None | 100% traffic hits new code immediately |
| Pre-deployment validation | None | No smoke test before switching traffic |
| Deployment alarm | None | No automatic rollback on error spike |
| Rollback mechanism | None | Must manually redeploy previous code |

### Deployment Anti-Patterns Found
| Anti-Pattern | What Happens | Better Approach |
|-------------|-------------|-----------------|
| Direct `update-function-code` | Immediate 100% deployment | CodeDeploy with canary (10% -> 100%) |
| No version published | Previous code lost | Publish version on every deploy |
| No health check after deploy | Silent failures | Validate /health before shifting traffic |
| No error threshold | Bad deploys persist | CloudWatch alarm triggers auto-rollback |

## Steps

```bash
# 1. Deploy broken code (simulates unsafe deployment)
./inject.sh [stack-name]

# 2. Observe the impact (silent data corruption)

# 3. Trigger DevOps Agent Evaluation
aws devops-agent create-backlog-task \
    --agent-space-id <your-space-id> \
    --task-type EVALUATION \
    --title "Evaluate deployment safety for Lambda functions" \
    --priority HIGH

# 4. Review recommendations
aws devops-agent list-recommendations \
    --agent-space-id <your-space-id> \
    --status PROPOSED

# 5. Rollback (manual - proving the gap)
./rollback.sh [stack-name]
```

## Expected Evaluation Output

1. **"Implement CodeDeploy for Lambda with canary deployment"** (HIGH)
   - Current deployment is all-at-once with no safety net
   - Agent-ready spec: SAM/CloudFormation for CodeDeploy + alias + canary10percent5minutes

2. **"Add deployment alarm with auto-rollback"** (HIGH)
   - No alarm monitors post-deployment health
   - Agent-ready spec: CloudWatch alarm on Errors metric + CodeDeploy rollback trigger

3. **"Enable Lambda versioning and publish on deploy"** (HIGH)
   - No version history means no rollback target
   - Agent-ready spec: CI/CD pipeline step to publish version + update alias

4. **"Add pre-deployment validation step"** (MEDIUM)
   - No smoke test before production traffic
   - Agent-ready spec: Pre-traffic hook Lambda that validates the new version

## Difficulty

**Advanced** -- Involves understanding CI/CD best practices, CodeDeploy Lambda integration, and traffic shifting patterns.

## Duration

- Inject: ~2 minutes (deploy + traffic)
- Wait: 3 minutes
- Evaluation: 5-10 minutes
- Rollback: 1 minute
- Total: ~16 minutes
