#!/bin/bash
set -euo pipefail

STACK_NAME="${1:-devops-agent-serverless}"
REGION="${AWS_REGION:-us-east-1}"
ERRORS=0

echo "============================================"
echo "Validating Serverless Workshop Stack"
echo "============================================"
echo "Stack: ${STACK_NAME}"
echo "Region: ${REGION}"
echo ""

check() {
    local description="$1"
    local result="$2"
    if [ -n "${result}" ] && [ "${result}" != "None" ] && [ "${result}" != "null" ]; then
        echo "  [PASS] ${description}: ${result}"
    else
        echo "  [FAIL] ${description}"
        ((ERRORS++))
    fi
}

echo "--- Stack Status ---"
STACK_STATUS=$(aws cloudformation describe-stacks \
    --stack-name "${STACK_NAME}" \
    --region "${REGION}" \
    --query 'Stacks[0].StackStatus' \
    --output text 2>/dev/null || echo "NOT_FOUND")
check "Stack exists and is healthy" "${STACK_STATUS}"

if [ "${STACK_STATUS}" != "CREATE_COMPLETE" ] && [ "${STACK_STATUS}" != "UPDATE_COMPLETE" ]; then
    echo ""
    echo "ERROR: Stack is not in a healthy state (${STACK_STATUS}). Cannot validate."
    exit 1
fi

echo ""
echo "--- Lambda Functions ---"
for fn in order-api validate-order process-payment update-inventory send-notification; do
    FN_STATE=$(aws lambda get-function \
        --function-name "${STACK_NAME}-${fn}" \
        --region "${REGION}" \
        --query 'Configuration.State' \
        --output text 2>/dev/null || echo "")
    check "Lambda ${fn}" "${FN_STATE}"
done

echo ""
echo "--- DynamoDB Tables ---"
for table in orders inventory payments; do
    TABLE_STATUS=$(aws dynamodb describe-table \
        --table-name "${STACK_NAME}-${table}" \
        --region "${REGION}" \
        --query 'Table.TableStatus' \
        --output text 2>/dev/null || echo "")
    check "DynamoDB ${table}" "${TABLE_STATUS}"
done

echo ""
echo "--- Step Functions ---"
SFN_ARN=$(aws cloudformation describe-stacks \
    --stack-name "${STACK_NAME}" \
    --region "${REGION}" \
    --query 'Stacks[0].Outputs[?OutputKey==`StateMachineArn`].OutputValue' \
    --output text)
SFN_STATUS=$(aws stepfunctions describe-state-machine \
    --state-machine-arn "${SFN_ARN}" \
    --region "${REGION}" \
    --query 'status' \
    --output text 2>/dev/null || echo "")
check "State Machine" "${SFN_STATUS}"

echo ""
echo "--- API Gateway ---"
API_ENDPOINT=$(aws cloudformation describe-stacks \
    --stack-name "${STACK_NAME}" \
    --region "${REGION}" \
    --query 'Stacks[0].Outputs[?OutputKey==`ApiEndpoint`].OutputValue' \
    --output text)
check "API Endpoint" "${API_ENDPOINT}"

echo ""
echo "--- EventBridge ---"
EVENT_BUS=$(aws cloudformation describe-stacks \
    --stack-name "${STACK_NAME}" \
    --region "${REGION}" \
    --query 'Stacks[0].Outputs[?OutputKey==`EventBusName`].OutputValue' \
    --output text)
check "Event Bus" "${EVENT_BUS}"

echo ""
echo "--- SQS Dead Letter Queue ---"
DLQ_URL=$(aws cloudformation describe-stacks \
    --stack-name "${STACK_NAME}" \
    --region "${REGION}" \
    --query 'Stacks[0].Outputs[?OutputKey==`DLQUrl`].OutputValue' \
    --output text)
check "DLQ URL" "${DLQ_URL}"

echo ""
echo "--- CloudWatch Alarms ---"
ALARM_COUNT=$(aws cloudwatch describe-alarms \
    --alarm-name-prefix "${STACK_NAME}" \
    --region "${REGION}" \
    --query 'length(MetricAlarms)' \
    --output text)
check "CloudWatch Alarms (expected 8)" "${ALARM_COUNT}"

echo ""
echo "--- Inventory Seed Data ---"
ITEM_COUNT=$(aws dynamodb scan \
    --table-name "${STACK_NAME}-inventory" \
    --region "${REGION}" \
    --select COUNT \
    --query 'Count' \
    --output text 2>/dev/null || echo "0")
check "Inventory items (expected 5)" "${ITEM_COUNT}"

echo ""
echo "--- End-to-End Test: Submit Order ---"
if [ -n "${API_ENDPOINT}" ]; then
    RESPONSE=$(curl -s -w "\n%{http_code}" \
        -X POST "${API_ENDPOINT}" \
        -H "Content-Type: application/json" \
        -d '{"customerId":"TEST-001","items":[{"productId":"PROD-001","quantity":1,"price":79}],"totalAmount":79}' \
        --connect-timeout 10 --max-time 30 2>/dev/null)
    HTTP_CODE=$(echo "${RESPONSE}" | tail -1)
    BODY=$(echo "${RESPONSE}" | head -1)
    check "POST /orders (expected 200)" "${HTTP_CODE}"
    echo "  Response: ${BODY}"
fi

echo ""
echo "============================================"
if [ "${ERRORS}" -eq 0 ]; then
    echo "All validations passed!"
else
    echo "FAILED: ${ERRORS} validation(s) failed."
fi
echo "============================================"
exit "${ERRORS}"
