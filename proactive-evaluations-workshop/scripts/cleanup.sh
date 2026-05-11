#!/bin/bash
set -euo pipefail

STACK_NAME="${1:-devops-eval}"
REGION="${AWS_REGION:-us-east-1}"

echo "============================================"
echo "Cleanup: Proactive Evaluations Workshop"
echo "============================================"
echo "Stack: ${STACK_NAME}"
echo "Region: ${REGION}"
echo ""

read -p "Are you sure you want to delete the stack '${STACK_NAME}'? (yes/no): " CONFIRM
if [ "${CONFIRM}" != "yes" ]; then
    echo "Aborted."
    exit 0
fi

echo "Deleting CloudFormation stack..."
aws cloudformation delete-stack \
    --stack-name "${STACK_NAME}" \
    --region "${REGION}"

echo "Waiting for stack deletion..."
aws cloudformation wait stack-delete-complete \
    --stack-name "${STACK_NAME}" \
    --region "${REGION}"

echo ""
echo "Stack '${STACK_NAME}' deleted successfully."
