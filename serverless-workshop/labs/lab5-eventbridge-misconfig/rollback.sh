#!/bin/bash
set -euo pipefail

STACK_NAME="${1:-devops-agent-serverless}"
REGION="${AWS_REGION:-us-east-1}"

EVENT_BUS_NAME=$(aws cloudformation describe-stacks \
    --stack-name "${STACK_NAME}" \
    --region "${REGION}" \
    --query 'Stacks[0].Outputs[?OutputKey==`EventBusName`].OutputValue' \
    --output text)

RULE_NAME="${STACK_NAME}-order-completed"

echo "============================================"
echo "Lab 5: EventBridge Misconfiguration - Rolling Back"
echo "============================================"

echo "Restoring original event pattern..."
aws events put-rule \
    --name "${RULE_NAME}" \
    --event-bus-name "${EVENT_BUS_NAME}" \
    --event-pattern '{
        "source": ["order.service"],
        "detail-type": ["OrderCompleted"]
    }' \
    --state ENABLED \
    --region "${REGION}" > /dev/null

echo "Rollback complete. EventBridge rule pattern restored."
echo "============================================"
