#!/bin/bash
set -euo pipefail

# Lab 2: Capacity Planning Gaps
# Demonstrates DevOps Agent identifying resources that will fail under load:
# - DynamoDB with low provisioned throughput and no auto-scaling
# - Lambda with no reserved concurrency
# - Auto Scaling Group with fixed size (no scaling policy)
# This lab generates sustained load to create visible capacity pressure.

STACK_NAME="${1:-devops-eval}"
REGION="${AWS_REGION:-us-east-1}"

echo "============================================"
echo "Lab 2: Capacity Planning Gaps - Inject"
echo "============================================"
echo ""

API_ENDPOINT=$(aws cloudformation describe-stacks \
    --stack-name "${STACK_NAME}" \
    --region "${REGION}" \
    --query 'Stacks[0].Outputs[?OutputKey==`ApiEndpoint`].OutputValue' \
    --output text)

ORDERS_TABLE=$(aws cloudformation describe-stacks \
    --stack-name "${STACK_NAME}" \
    --region "${REGION}" \
    --query 'Stacks[0].Outputs[?OutputKey==`OrdersTableName`].OutputValue' \
    --output text)

ASG_NAME=$(aws cloudformation describe-stacks \
    --stack-name "${STACK_NAME}" \
    --region "${REGION}" \
    --query 'Stacks[0].Outputs[?OutputKey==`AutoScalingGroupName`].OutputValue' \
    --output text)

echo "Step 1: Showing current capacity configuration..."
echo ""
echo "DynamoDB Orders table:"
aws dynamodb describe-table \
    --table-name "${ORDERS_TABLE}" \
    --region "${REGION}" \
    --query 'Table.ProvisionedThroughput' \
    --output table

echo ""
echo "Auto Scaling Group:"
aws autoscaling describe-auto-scaling-groups \
    --auto-scaling-group-names "${ASG_NAME}" \
    --region "${REGION}" \
    --query 'AutoScalingGroups[0].{Min:MinSize,Max:MaxSize,Desired:DesiredCapacity}' \
    --output table

echo ""
echo "Auto Scaling Policies (should be empty):"
aws autoscaling describe-policies \
    --auto-scaling-group-name "${ASG_NAME}" \
    --region "${REGION}" \
    --query 'ScalingPolicies[*].PolicyName' \
    --output table 2>/dev/null || echo "  (none configured)"

echo ""
echo "Step 2: Generating burst traffic to create capacity pressure..."
echo "  (60 rapid requests to stress DynamoDB provisioned capacity)"
echo ""

THROTTLES=0
SUCCESS=0

for i in $(seq 1 60); do
    HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" \
        -X POST "${API_ENDPOINT}/orders" \
        -H "Content-Type: application/json" \
        -d "{\"customerId\":\"burst-${i}\",\"items\":[{\"productId\":\"PROD-001\",\"quantity\":$((RANDOM % 3 + 1))},{\"productId\":\"PROD-002\",\"quantity\":$((RANDOM % 5 + 1))}],\"totalAmount\":$((RANDOM % 300 + 50))}" \
        --connect-timeout 5 --max-time 30 2>/dev/null || echo "000")

    if [ "${HTTP_CODE}" = "200" ]; then
        SUCCESS=$((SUCCESS + 1))
    else
        THROTTLES=$((THROTTLES + 1))
    fi
    printf "\r  Progress: %d/60 (success: %d, errors: %d)" "$i" "${SUCCESS}" "${THROTTLES}"
    # Rapid-fire (no sleep) to stress capacity
done

echo ""
echo ""
echo "Step 3: Checking DynamoDB consumed capacity..."
echo ""

aws cloudwatch get-metric-statistics \
    --namespace AWS/DynamoDB \
    --metric-name ConsumedWriteCapacityUnits \
    --dimensions Name=TableName,Value="${ORDERS_TABLE}" \
    --start-time "$(date -u -d '5 minutes ago' '+%Y-%m-%dT%H:%M:%SZ' 2>/dev/null || date -u -v-5M '+%Y-%m-%dT%H:%M:%SZ')" \
    --end-time "$(date -u '+%Y-%m-%dT%H:%M:%SZ')" \
    --period 60 \
    --statistics Maximum \
    --region "${REGION}" \
    --query 'Datapoints[*].[Timestamp,Maximum]' \
    --output table 2>/dev/null || echo "  (metrics not yet available)"

echo ""
echo "============================================"
echo "Lab 2 Setup Complete"
echo ""
echo "CAPACITY GAPS for DevOps Agent to discover:"
echo ""
echo "  DynamoDB:"
echo "    - Orders table: 5 WCU provisioned, no auto-scaling"
echo "    - Inventory table: 3 RCU/WCU, no auto-scaling"
echo "    - GSI customer-index: 2 WCU (bottleneck)"
echo "    - No on-demand billing mode"
echo ""
echo "  Lambda:"
echo "    - No reserved concurrency (shared pool)"
echo "    - order-processor: 128MB may be insufficient"
echo "    - Timeout 300s too generous (masks hangs)"
echo ""
echo "  Auto Scaling:"
echo "    - Min=Max=2 (cannot scale out)"
echo "    - No target tracking policy"
echo "    - No scheduled scaling for peaks"
echo ""
echo "EVALUATION PROMPT for DevOps Agent:"
echo "  'Evaluate capacity planning for resources tagged"
echo "   devopsagent=true. Identify resources that cannot"
echo "   handle traffic spikes and recommend auto-scaling.'"
echo "============================================"
