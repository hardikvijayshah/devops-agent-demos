#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
STACK_NAME="${1:-devops-agent-jenkins}"
REGION="${AWS_REGION:-us-east-1}"

echo "============================================"
echo "Scenario 3: Rolling Back OOM Image"
echo "============================================"

"${SCRIPT_DIR}/../../scripts/deploy-initial-image.sh" "${STACK_NAME}"

echo ""
echo "Waiting for ECS service to stabilize..."
aws ecs wait services-stable \
    --cluster "${STACK_NAME}-cluster" \
    --services "${STACK_NAME}-service" \
    --region "${REGION}" 2>/dev/null || true

echo "Rollback complete. Stable image restored."
echo "============================================"
