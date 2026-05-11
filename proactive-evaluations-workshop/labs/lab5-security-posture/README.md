# Lab 5: Security Posture Gaps

## Scenario

The infrastructure has **multiple security weaknesses** -- an unauthenticated API, overly broad IAM permissions, no encryption, no WAF, and no rate limiting. These gaps won't cause immediate operational issues but represent significant security risk.

DevOps Agent evaluates the security posture and identifies hardening opportunities before they're exploited.

## What DevOps Agent Should Discover

### API Security Gaps
| Gap | Current State | Recommendation |
|-----|--------------|----------------|
| Authentication | AuthorizationType: NONE | Cognito authorizer or IAM auth |
| Rate limiting | No usage plan | API key + usage plan (1000 req/sec) |
| WAF | Not attached | AWS WAF with managed rule groups |
| Request validation | None | Request validator on model schema |
| CORS | Not configured | Restrict to known origins |

### IAM Permission Issues
| Issue | Detail | Fix |
|-------|--------|-----|
| Broad DynamoDB actions | Includes Scan, DeleteItem | Remove unused actions |
| No conditions | No aws:SourceAccount condition | Add account restriction |
| Shared role | All functions share one role | Per-function least-privilege roles |

### Encryption Gaps
| Resource | Status | Recommendation |
|----------|--------|----------------|
| SNS Topic | Not encrypted | Add KMS key |
| DynamoDB Tables | AWS-managed key | Customer-managed key (CMK) |
| API Gateway | TLS only (no payload encryption) | Consider field-level encryption |

### Network Security
| Gap | Risk | Fix |
|-----|------|-----|
| Lambda not in VPC | Can reach internet | Deploy in VPC with NAT |
| No VPC endpoints | DynamoDB traffic via internet | Add DynamoDB VPC endpoint |
| No WAF on ALB | No DDoS/bot protection | Attach WAF web ACL |

## Steps

```bash
# 1. Demonstrate security gaps
./inject.sh [stack-name]

# 2. Trigger DevOps Agent Evaluation
aws devops-agent create-backlog-task \
    --agent-space-id <your-space-id> \
    --task-type EVALUATION \
    --title "Evaluate security posture for devops-eval resources" \
    --priority HIGH

# 3. Review recommendations
aws devops-agent list-recommendations \
    --agent-space-id <your-space-id> \
    --status PROPOSED
```

## Expected Evaluation Output

1. **"Add authentication to API Gateway"** (HIGH)
   - API is completely open (no auth, no API key)
   - Agent-ready spec: Cognito user pool + authorizer configuration

2. **"Attach WAF web ACL to API Gateway and ALB"** (HIGH)
   - No protection against common web attacks or DDoS
   - Agent-ready spec: WAF web ACL with AWS managed rule groups

3. **"Add API Gateway usage plan with throttling"** (HIGH)
   - No rate limiting allows abuse
   - Agent-ready spec: Usage plan + API key configuration

4. **"Enable KMS encryption on SNS topic"** (MEDIUM)
   - Messages in transit between services are not encrypted at rest
   - Agent-ready spec: KMS key + SNS topic encryption configuration

5. **"Apply least-privilege IAM to Lambda functions"** (MEDIUM)
   - Shared role with unnecessary permissions (Scan, DeleteItem)
   - Agent-ready spec: Per-function roles with minimal actions

## Difficulty

**Advanced** -- Requires understanding of AWS security best practices, IAM policy design, and defense-in-depth architecture.

## Duration

- Inject: ~2 minutes (demonstrations)
- Evaluation: 5-10 minutes
- Total: ~12 minutes
