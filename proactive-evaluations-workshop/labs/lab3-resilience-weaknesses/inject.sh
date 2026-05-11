#!/bin/bash
set -euo pipefail

# Lab 3: Application Resilience Weaknesses
# Demonstrates DevOps Agent identifying code-level resilience gaps:
# - No retry logic in Lambda functions
# - No DLQ for Lambda failures
# - No circuit breaker pattern
# - No input validation
# - Full table scans instead of targeted queries
# This lab creates transient failures to highlight missing resilience.

STACK_NAME="${1:-devops-eval}"
REGION="${AWS_REGION:-us-east-1}"

echo "============================================"
echo "Lab 3: Application Resilience Weaknesses - Inject"
echo "============================================"
echo ""

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

echo "Step 1: Sending requests that expose resilience gaps..."
echo ""

echo "  Testing: No input validation..."
# Send requests with missing required fields
for i in $(seq 1 5); do
    curl -s -o /dev/null -X POST "${API_ENDPOINT}/orders" \
        -H "Content-Type: application/json" \
        -d "{}" \
        --connect-timeout 5 --max-time 30 2>/dev/null || true
done
echo "    Sent 5 requests with empty body (no validation = 500 error)"

# Send requests with wrong types
for i in $(seq 1 5); do
    curl -s -o /dev/null -X POST "${API_ENDPOINT}/orders" \
        -H "Content-Type: application/json" \
        -d "{\"customerId\":123,\"items\":\"not-an-array\",\"totalAmount\":\"free\"}" \
        --connect-timeout 5 --max-time 30 2>/dev/null || true
done
echo "    Sent 5 requests with wrong types (no type checking = 500 error)"

echo ""
echo "  Testing: No retry logic under throttle pressure..."
# Rapid-fire to trigger DynamoDB throttling (no retry)
for i in $(seq 1 30); do
    curl -s -o /dev/null -X POST "${API_ENDPOINT}/orders" \
        -H "Content-Type: application/json" \
        -d "{\"customerId\":\"retry-test-${i}\",\"items\":[{\"productId\":\"PROD-001\",\"quantity\":1}],\"totalAmount\":79}" \
        --connect-timeout 5 --max-time 30 2>/dev/null || true
done
echo "    Sent 30 rapid requests (throttled writes fail permanently - no retry)"

echo ""
echo "  Testing: Table scan performance..."
# Hit inventory endpoint repeatedly (full table scan each time)
for i in $(seq 1 20); do
    curl -s -o /dev/null "${API_ENDPOINT}/inventory" \
        --connect-timeout 5 --max-time 30 2>/dev/null || true
done
echo "    Sent 20 inventory requests (each does full table scan)"

echo ""
echo "Step 2: Checking Lambda error logs for unhandled exceptions..."
echo ""

aws logs filter-log-events \
    --log-group-name "/aws/lambda/${STACK_NAME}-order-processor" \
    --start-time $(($(date +%s) * 1000 - 300000)) \
    --filter-pattern "ERROR" \
    --region "${REGION}" \
    --query 'events[0:3].message' \
    --output text 2>/dev/null || echo "  (logs not yet available)"

echo ""
echo "Step 3: Checking Lambda DLQ configuration..."
echo ""

DLQ_ARN=$(aws lambda get-function-configuration \
    --function-name "${ORDER_FUNCTION}" \
    --region "${REGION}" \
    --query 'DeadLetterConfig.TargetArn' \
    --output text 2>/dev/null || echo "None")

echo "  Order processor DLQ: ${DLQ_ARN}"

echo ""
echo "============================================"
echo "Lab 3 Setup Complete"
echo ""
echo "RESILIENCE GAPS for DevOps Agent to discover:"
echo ""
echo "  CODE QUALITY:"
echo "    - No input validation (KeyError on missing fields)"
echo "    - No type checking (TypeError on wrong types)"
echo "    - No error handling wrapper (unhandled exceptions)"
echo ""
echo "  FAULT TOLERANCE:"
echo "    - No retry logic for DynamoDB throttled writes"
echo "    - No exponential backoff"
echo "    - No circuit breaker pattern"
echo "    - No DLQ configured (failed events lost forever)"
echo ""
echo "  PERFORMANCE:"
echo "    - Full table scan in inventory checker (O(n) cost)"
echo "    - No pagination for large result sets"
echo "    - Session cleanup scans + deletes one-by-one"
echo ""
echo "EVALUATION PROMPT for DevOps Agent:"
echo "  'Evaluate application resilience for Lambda functions"
echo "   tagged devopsagent=true. Check for retry logic,"
echo "   error handling, DLQ configuration, and code quality.'"
echo "============================================"
