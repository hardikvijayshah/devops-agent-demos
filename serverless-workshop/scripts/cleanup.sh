#!/bin/bash
set -euo pipefail

STACK_NAME="${1:-devops-agent-serverless}"
REGION="${AWS_REGION:-us-east-1}"

echo "============================================"
echo "AWS DevOps Agent - Serverless Workshop Cleanup"
echo "============================================"
echo "Stack Name:  ${STACK_NAME}"
echo "Region:      ${REGION}"
echo ""

read -p "Are you sure you want to delete the stack '${STACK_NAME}'? (y/N): " confirm
if [[ "${confirm}" != "y" && "${confirm}" != "Y" ]]; then
    echo "Cleanup cancelled."
    exit 0
fi

echo "Deleting CloudFormation stack..."
aws cloudformation delete-stack \
    --stack-name "${STACK_NAME}" \
    --region "${REGION}"

echo "Waiting for stack deletion to complete..."
aws cloudformation wait stack-delete-complete \
    --stack-name "${STACK_NAME}" \
    --region "${REGION}"

echo ""
echo "============================================"
echo "Stack '${STACK_NAME}' has been deleted."
echo "============================================"
