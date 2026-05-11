#!/bin/bash
set -euo pipefail

STACK_NAME="${1:-devops-agent-serverless}"
REGION="${AWS_REGION:-us-east-1}"

EVENT_BUS_NAME=$(aws cloudformation describe-stacks \
    --stack-name "${STACK_NAME}" \
    --region "${REGION}" \
    --query 'Stacks[0].Outputs[?OutputKey==`EventBusName`].OutputValue' \
    --output text)

echo "============================================"
echo "Lab 5: EventBridge Misconfiguration - Injecting Failure"
echo "============================================"
echo "Event Bus: ${EVENT_BUS_NAME}"
echo ""

RULE_NAME="${STACK_NAME}-order-completed"

echo "Saving current rule event pattern..."
CURRENT_PATTERN=$(aws events describe-rule \
    --name "${RULE_NAME}" \
    --event-bus-name "${EVENT_BUS_NAME}" \
    --region "${REGION}" \
    --query 'EventPattern' \
    --output text)
echo "${CURRENT_PATTERN}" > /tmp/lab5-original-pattern.json
echo "Original pattern: ${CURRENT_PATTERN}"

echo ""
echo "Updating rule with non-matching event pattern..."
aws events put-rule \
    --name "${RULE_NAME}" \
    --event-bus-name "${EVENT_BUS_NAME}" \
    --event-pattern '{
        "source": ["order.service.v2"],
        "detail-type": ["OrderCompletedV2"]
    }' \
    --state ENABLED \
    --region "${REGION}" > /dev/null

echo ""
echo "============================================"
echo "Failure injected!"
echo ""
echo "The order-completed EventBridge rule now expects:"
echo "  - source: 'order.service.v2' (actual: 'order.service')"
echo "  - detail-type: 'OrderCompletedV2' (actual: 'OrderCompleted')"
echo ""
echo "Events will be published but no rule will match them."
echo "Order completion notifications will silently stop."
echo ""
echo "Next steps:"
echo "  1. Generate traffic: ../../scripts/generate-traffic.sh ${STACK_NAME} 15 2"
echo "  2. Check that orders complete but no notifications arrive"
echo "  3. Ask DevOps Agent to investigate the notification gap"
echo ""
echo "Expected DevOps Agent findings:"
echo "  - EventBridge rule pattern doesn't match published events"
echo "  - SNS notification delivery dropped to zero"
echo "  - Rule configuration change detected"
echo ""
echo "To rollback: ./rollback.sh ${STACK_NAME}"
echo "============================================"
