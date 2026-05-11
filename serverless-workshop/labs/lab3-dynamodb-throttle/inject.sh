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
echo "Lab 3: DynamoDB Throttling - Injecting Failure"
echo "============================================"
echo "Table: ${INVENTORY_TABLE}"
echo ""

echo "Saving current provisioned throughput..."
CURRENT_THROUGHPUT=$(aws dynamodb describe-table \
    --table-name "${INVENTORY_TABLE}" \
    --region "${REGION}" \
    --query 'Table.ProvisionedThroughput.{RCU: ReadCapacityUnits, WCU: WriteCapacityUnits}' \
    --output json)
echo "${CURRENT_THROUGHPUT}" > /tmp/lab3-original-throughput.json
echo "Original throughput: ${CURRENT_THROUGHPUT}"

echo ""
echo "Reducing write capacity to 1 WCU and read capacity to 1 RCU..."
aws dynamodb update-table \
    --table-name "${INVENTORY_TABLE}" \
    --provisioned-throughput ReadCapacityUnits=1,WriteCapacityUnits=1 \
    --region "${REGION}" > /dev/null

echo "Waiting for table update..."
aws dynamodb wait table-exists \
    --table-name "${INVENTORY_TABLE}" \
    --region "${REGION}"

echo ""
echo "============================================"
echo "Failure injected!"
echo ""
echo "The inventory table now has:"
echo "  - Read Capacity:  1 RCU (was 5)"
echo "  - Write Capacity: 1 WCU (was 5)"
echo ""
echo "Next steps:"
echo "  1. Generate heavy traffic: ../../scripts/generate-traffic.sh ${STACK_NAME} 50 0.5"
echo "  2. Wait 2-3 minutes for throttling alarm"
echo "  3. Observe DevOps Agent investigation"
echo ""
echo "Expected DevOps Agent findings:"
echo "  - DynamoDB WriteThrottleEvents on inventory table"
echo "  - Cascading failures in update-inventory Lambda"
echo "  - Step Functions executions failing at UpdateInventory state"
echo "  - Recommendation to increase provisioned throughput or switch to on-demand"
echo ""
echo "To rollback: ./rollback.sh ${STACK_NAME}"
echo "============================================"
