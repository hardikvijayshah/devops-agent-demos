#!/bin/bash
set -euo pipefail

STACK_NAME="${1:-devops-agent-serverless}"
REGION="${AWS_REGION:-us-east-1}"

FUNCTION_NAME=$(aws cloudformation describe-stacks \
    --stack-name "${STACK_NAME}" \
    --region "${REGION}" \
    --query 'Stacks[0].Outputs[?OutputKey==`ValidateOrderFunctionName`].OutputValue' \
    --output text)

echo "============================================"
echo "Lab 2: Step Functions Failure - Injecting Failure"
echo "============================================"
echo "Function: ${FUNCTION_NAME}"
echo ""

echo "Saving current function code..."
aws lambda get-function \
    --function-name "${FUNCTION_NAME}" \
    --region "${REGION}" \
    --query 'Code.Location' \
    --output text > /tmp/lab2-code-url.txt

echo "Deploying broken validation code (always raises exception)..."
BROKEN_CODE=$(cat <<'PYEOF'
import json
import os
import time

def handler(event, context):
    # Simulate a broken JSONPath / data format issue
    # The function expects 'items' but tries to access a non-existent nested path
    order = event

    # This will fail because we're trying to access a nested structure
    # that doesn't exist in the Step Functions input
    item_details = order['orderDetails']['itemList']['entries']

    # This line is never reached
    return {**order, 'validated': True}
PYEOF
)

TEMP_DIR=$(mktemp -d)
echo "${BROKEN_CODE}" > "${TEMP_DIR}/index.py"
cd "${TEMP_DIR}" && zip -q function.zip index.py

aws lambda update-function-code \
    --function-name "${FUNCTION_NAME}" \
    --zip-file "fileb://${TEMP_DIR}/function.zip" \
    --region "${REGION}" > /dev/null

aws lambda wait function-updated \
    --function-name "${FUNCTION_NAME}" \
    --region "${REGION}"

rm -rf "${TEMP_DIR}"

echo ""
echo "============================================"
echo "Failure injected!"
echo ""
echo "The validate-order Lambda now has broken code that tries"
echo "to access a non-existent nested path in the order data."
echo "This causes KeyError exceptions on every invocation."
echo ""
echo "Next steps:"
echo "  1. Generate traffic: ../../scripts/generate-traffic.sh ${STACK_NAME}"
echo "  2. Wait 2-3 minutes for Step Functions failure alarm"
echo "  3. Observe DevOps Agent investigation"
echo ""
echo "Expected DevOps Agent findings:"
echo "  - Step Functions executions failing at ValidateOrder state"
echo "  - KeyError in validate-order Lambda CloudWatch Logs"
echo "  - Code change correlation with failure onset"
echo ""
echo "To rollback: ./rollback.sh ${STACK_NAME}"
echo "============================================"
