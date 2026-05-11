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
echo "Lab 1: Lambda Timeout - Rolling Back"
echo "============================================"

echo "Restoring original configuration (timeout: 30s, memory: 256MB)..."
aws lambda update-function-configuration \
    --function-name "${FUNCTION_NAME}" \
    --timeout 30 \
    --memory-size 256 \
    --region "${REGION}" > /dev/null

aws lambda wait function-updated \
    --function-name "${FUNCTION_NAME}" \
    --region "${REGION}"

echo "Rollback complete. Function restored to original configuration."
echo "============================================"
