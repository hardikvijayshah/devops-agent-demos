#!/bin/bash
set -euo pipefail

STACK_NAME="${1:-devops-agent-serverless}"
REGION="${AWS_REGION:-us-east-1}"

INVENTORY_TABLE=$(aws cloudformation describe-stacks \
    --stack-name "${STACK_NAME}" \
    --region "${REGION}" \
    --query 'Stacks[0].Outputs[?OutputKey==`InventoryTableName`].OutputValue' \
    --output text)

echo "============================================"
echo "Lab 3: DynamoDB Throttling - Rolling Back"
echo "============================================"

echo "Restoring provisioned throughput to 5 RCU / 5 WCU..."
aws dynamodb update-table \
    --table-name "${INVENTORY_TABLE}" \
    --provisioned-throughput ReadCapacityUnits=5,WriteCapacityUnits=5 \
    --region "${REGION}" > /dev/null

aws dynamodb wait table-exists \
    --table-name "${INVENTORY_TABLE}" \
    --region "${REGION}"

echo "Rollback complete. Inventory table throughput restored."
echo "============================================"
