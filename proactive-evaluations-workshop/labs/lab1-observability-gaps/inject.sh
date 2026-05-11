#!/bin/bash
set -euo pipefail

# Lab 1: Observability Gaps
# This lab generates traffic to create metric data points, then triggers
# a DevOps Agent Evaluation to identify missing alarms and monitoring gaps.
# The infrastructure is ALREADY deployed with gaps - this lab makes them visible.

STACK_NAME="${1:-devops-eval}"
REGION="${AWS_REGION:-us-east-1}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "============================================"
echo "Lab 1: Observability Gaps - Inject"
echo "============================================"
echo ""
echo "This lab demonstrates DevOps Agent's ability to identify:"
echo "  - Missing CloudWatch alarms"
echo "  - Alarm thresholds that are too lenient"
echo "  - Missing metric filters"
echo "  - Unmonitored resources"
echo ""

# Get stack outputs
API_ENDPOINT=$(aws cloudformation describe-stacks \
    --stack-name "${STACK_NAME}" \
    --region "${REGION}" \
    --query 'Stacks[0].Outputs[?OutputKey==`ApiEndpoint`].OutputValue' \
    --output text)

ORDER_FUNCTION=$(aws cloudformation describe-stacks \
    --stack-name "${STACK_NAME}" \
    --region "${REGION}" \
    --query 'Stacks[0].Outputs[?OutputKey==`OrderProcessorFunction`].OutputValue' \
    --output text)

echo "Step 1: Generating mixed traffic (success + errors) to populate metrics..."
echo ""

# Generate orders that will succeed
for i in $(seq 1 15); do
    curl -s -o /dev/null -X POST "${API_ENDPOINT}/orders" \
        -H "Content-Type: application/json" \
        -d "{\"customerId\":\"cust-00${i}\",\"items\":[{\"productId\":\"PROD-001\",\"quantity\":1}],\"totalAmount\":79}" \
        --connect-timeout 5 --max-time 30 2>/dev/null || true
    sleep 1
done
echo "  Sent 15 valid orders."

# Generate orders that will fail (missing fields)
for i in $(seq 1 10); do
    curl -s -o /dev/null -X POST "${API_ENDPOINT}/orders" \
        -H "Content-Type: application/json" \
        -d "{\"invalid\":\"data\"}" \
        --connect-timeout 5 --max-time 30 2>/dev/null || true
    sleep 1
done
echo "  Sent 10 invalid orders (will cause errors)."

# Generate orders for non-existent products
for i in $(seq 1 5); do
    curl -s -o /dev/null -X POST "${API_ENDPOINT}/orders" \
        -H "Content-Type: application/json" \
        -d "{\"customerId\":\"cust-001\",\"items\":[{\"productId\":\"PROD-999\",\"quantity\":1}],\"totalAmount\":50}" \
        --connect-timeout 5 --max-time 30 2>/dev/null || true
    sleep 1
done
echo "  Sent 5 orders for non-existent products."

echo ""
echo "Step 2: Listing current alarm coverage..."
echo ""

ALARM_COUNT=$(aws cloudwatch describe-alarms \
    --alarm-name-prefix "${STACK_NAME}" \
    --region "${REGION}" \
    --query 'MetricAlarms | length(@)' \
    --output text)

echo "  Current alarm count: ${ALARM_COUNT}"
echo ""
echo "  Alarms present:"
aws cloudwatch describe-alarms \
    --alarm-name-prefix "${STACK_NAME}" \
    --region "${REGION}" \
    --query 'MetricAlarms[*].AlarmName' \
    --output table

echo ""
echo "============================================"
echo "Lab 1 Setup Complete"
echo ""
echo "OBSERVABILITY GAPS for DevOps Agent to discover:"
echo ""
echo "  MISSING ALARMS:"
echo "    - No DynamoDB ConsumedWriteCapacityUnits alarm"
echo "    - No DynamoDB ThrottledRequests alarm"
echo "    - No Lambda Duration alarm"
echo "    - No Lambda ConcurrentExecutions alarm"
echo "    - No Lambda Throttles alarm"
echo "    - No ALB TargetResponseTime alarm"
echo "    - No ALB RequestCount anomaly alarm"
echo "    - No API Gateway Latency alarm"
echo ""
echo "  LENIENT THRESHOLDS:"
echo "    - Lambda errors: threshold=50 (should be 3-5)"
echo "    - ALB unhealthy: threshold=2, period=5min (should be 1, 1min)"
echo "    - API 5xx: threshold=100 (should be 5-10)"
echo ""
echo "  MISSING MONITORING:"
echo "    - No X-Ray tracing on Lambda or API Gateway"
echo "    - No CloudWatch metric filters for application errors"
echo "    - No dashboard for operational visibility"
echo ""
echo "INVESTIGATION PROMPT for DevOps Agent:"
echo "  'Evaluate the observability posture of resources tagged"
echo "   devopsagent=true. Identify missing alarms, lenient"
echo "   thresholds, and monitoring gaps.'"
echo "============================================"
