#!/bin/bash
set -euo pipefail

STACK_NAME="${1:-devops-agent-serverless}"
REGION="${AWS_REGION:-us-east-1}"

FUNCTION_NAME=$(aws cloudformation describe-stacks \
    --stack-name "${STACK_NAME}" \
    --region "${REGION}" \
    --query 'Stacks[0].Outputs[?OutputKey==`OrderApiFunctionName`].OutputValue' \
    --output text)

echo "============================================"
echo "Lab 1: Lambda Timeout - Injecting Failure"
echo "============================================"
echo "Function: ${FUNCTION_NAME}"
echo ""

echo "Saving current configuration..."
CURRENT_CONFIG=$(aws lambda get-function-configuration \
    --function-name "${FUNCTION_NAME}" \
    --region "${REGION}" \
    --query '{Timeout: Timeout, MemorySize: MemorySize}' \
    --output json)
echo "${CURRENT_CONFIG}" > /tmp/lab1-original-config.json
echo "Original config saved: ${CURRENT_CONFIG}"

echo ""
echo "Reducing timeout to 1 second and memory to 128MB..."
aws lambda update-function-configuration \
    --function-name "${FUNCTION_NAME}" \
    --timeout 1 \
    --memory-size 128 \
    --region "${REGION}" > /dev/null

echo ""
echo "Waiting for function update to complete..."
aws lambda wait function-updated \
    --function-name "${FUNCTION_NAME}" \
    --region "${REGION}"

echo ""
echo "============================================"
echo "Failure injected!"
echo ""
echo "The order-api Lambda now has:"
echo "  - Timeout: 1 second (was 30s)"
echo "  - Memory: 128 MB (was 256MB)"
echo ""
echo "Next steps:"
echo "  1. Generate traffic: ../../scripts/generate-traffic.sh ${STACK_NAME}"
echo "  2. Wait 2-3 minutes for CloudWatch alarms to trigger"
echo "  3. Observe DevOps Agent investigation"
echo ""
echo "Expected DevOps Agent findings:"
echo "  - Lambda timeout errors in CloudWatch Logs"
echo "  - Correlation between reduced timeout/memory and error spike"
echo "  - Recommendation to increase timeout and memory"
echo ""
echo "To rollback: ./rollback.sh ${STACK_NAME}"
echo "============================================"
