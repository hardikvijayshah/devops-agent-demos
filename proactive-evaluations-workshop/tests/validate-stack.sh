#!/bin/bash
set -euo pipefail

STACK_NAME="${1:-devops-eval}"
REGION="${AWS_REGION:-us-east-1}"
PASS=0
FAIL=0

check() {
    local desc="$1"
    local result="$2"
    if [ "${result}" = "PASS" ]; then
        echo "  [PASS] ${desc}"
        PASS=$((PASS + 1))
    else
        echo "  [FAIL] ${desc} -- ${result}"
        FAIL=$((FAIL + 1))
    fi
}

echo "============================================"
echo "Validate: Proactive Evaluations Workshop"
echo "============================================"
echo "Stack: ${STACK_NAME}"
echo "Region: ${REGION}"
echo ""

# 1. Stack status
echo "--- Stack Status ---"
STACK_STATUS=$(aws cloudformation describe-stacks \
    --stack-name "${STACK_NAME}" \
    --region "${REGION}" \
    --query 'Stacks[0].StackStatus' \
    --output text 2>/dev/null || echo "NOT_FOUND")
if [ "${STACK_STATUS}" = "CREATE_COMPLETE" ] || [ "${STACK_STATUS}" = "UPDATE_COMPLETE" ]; then
    check "Stack status" "PASS"
else
    check "Stack status" "${STACK_STATUS}"
fi

# 2. DynamoDB tables
echo ""
echo "--- DynamoDB Tables ---"
for TABLE in orders inventory sessions; do
    STATUS=$(aws dynamodb describe-table \
        --table-name "${STACK_NAME}-${TABLE}" \
        --region "${REGION}" \
        --query 'Table.TableStatus' \
        --output text 2>/dev/null || echo "NOT_FOUND")
    if [ "${STATUS}" = "ACTIVE" ]; then
        check "Table ${STACK_NAME}-${TABLE}" "PASS"
    else
        check "Table ${STACK_NAME}-${TABLE}" "${STATUS}"
    fi
done

# 3. Lambda functions
echo ""
echo "--- Lambda Functions ---"
for FUNC in order-processor inventory-checker session-cleanup seed-data; do
    STATE=$(aws lambda get-function \
        --function-name "${STACK_NAME}-${FUNC}" \
        --region "${REGION}" \
        --query 'Configuration.State' \
        --output text 2>/dev/null || echo "NOT_FOUND")
    if [ "${STATE}" = "Active" ]; then
        check "Lambda ${STACK_NAME}-${FUNC}" "PASS"
    else
        check "Lambda ${STACK_NAME}-${FUNC}" "${STATE}"
    fi
done

# 4. API Gateway
echo ""
echo "--- API Gateway ---"
API_ENDPOINT=$(aws cloudformation describe-stacks \
    --stack-name "${STACK_NAME}" \
    --region "${REGION}" \
    --query 'Stacks[0].Outputs[?OutputKey==`ApiEndpoint`].OutputValue' \
    --output text 2>/dev/null || echo "")
if [ -n "${API_ENDPOINT}" ]; then
    check "API Gateway endpoint exists" "PASS"
    HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" \
        "${API_ENDPOINT}/inventory" \
        --connect-timeout 5 --max-time 10 2>/dev/null || echo "000")
    if [ "${HTTP_CODE}" = "200" ]; then
        check "API Gateway /inventory responds 200" "PASS"
    else
        check "API Gateway /inventory responds 200" "HTTP ${HTTP_CODE}"
    fi
else
    check "API Gateway endpoint exists" "NOT_FOUND"
fi

# 5. ALB
echo ""
echo "--- Application Load Balancer ---"
ALB_ENDPOINT=$(aws cloudformation describe-stacks \
    --stack-name "${STACK_NAME}" \
    --region "${REGION}" \
    --query 'Stacks[0].Outputs[?OutputKey==`ALBEndpoint`].OutputValue' \
    --output text 2>/dev/null || echo "")
if [ -n "${ALB_ENDPOINT}" ]; then
    check "ALB endpoint exists" "PASS"
    HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" \
        "${ALB_ENDPOINT}/health" \
        --connect-timeout 5 --max-time 10 2>/dev/null || echo "000")
    if [ "${HTTP_CODE}" = "200" ]; then
        check "ALB /health responds 200" "PASS"
    else
        check "ALB /health responds 200" "HTTP ${HTTP_CODE}"
    fi
else
    check "ALB endpoint exists" "NOT_FOUND"
fi

# 6. Auto Scaling Group
echo ""
echo "--- Auto Scaling Group ---"
ASG_NAME=$(aws cloudformation describe-stacks \
    --stack-name "${STACK_NAME}" \
    --region "${REGION}" \
    --query 'Stacks[0].Outputs[?OutputKey==`AutoScalingGroupName`].OutputValue' \
    --output text 2>/dev/null || echo "")
if [ -n "${ASG_NAME}" ]; then
    INSTANCE_COUNT=$(aws autoscaling describe-auto-scaling-groups \
        --auto-scaling-group-names "${ASG_NAME}" \
        --region "${REGION}" \
        --query 'AutoScalingGroups[0].Instances | length(@)' \
        --output text 2>/dev/null || echo "0")
    if [ "${INSTANCE_COUNT}" -ge 2 ]; then
        check "ASG has 2+ instances" "PASS"
    else
        check "ASG has 2+ instances" "Only ${INSTANCE_COUNT}"
    fi
fi

# 7. CloudWatch Alarms
echo ""
echo "--- CloudWatch Alarms ---"
ALARM_COUNT=$(aws cloudwatch describe-alarms \
    --alarm-name-prefix "${STACK_NAME}" \
    --region "${REGION}" \
    --query 'MetricAlarms | length(@)' \
    --output text 2>/dev/null || echo "0")
if [ "${ALARM_COUNT}" -eq 3 ]; then
    check "Exactly 3 alarms deployed (intentional gap)" "PASS"
else
    check "Exactly 3 alarms deployed (intentional gap)" "Found ${ALARM_COUNT}"
fi

# 8. Seed data
echo ""
echo "--- Seed Data ---"
ITEM_COUNT=$(aws dynamodb scan \
    --table-name "${STACK_NAME}-inventory" \
    --region "${REGION}" \
    --select COUNT \
    --query 'Count' \
    --output text 2>/dev/null || echo "0")
if [ "${ITEM_COUNT}" -ge 8 ]; then
    check "Inventory table has 8 products" "PASS"
else
    check "Inventory table has 8 products" "Only ${ITEM_COUNT}"
fi

# 9. Verify intentional gaps exist
echo ""
echo "--- Intentional Gaps (should all PASS) ---"

# No X-Ray on Lambda
TRACING=$(aws lambda get-function-configuration \
    --function-name "${STACK_NAME}-order-processor" \
    --region "${REGION}" \
    --query 'TracingConfig.Mode' \
    --output text 2>/dev/null || echo "Unknown")
if [ "${TRACING}" = "PassThrough" ]; then
    check "Lambda X-Ray disabled (intentional gap)" "PASS"
else
    check "Lambda X-Ray disabled (intentional gap)" "Mode: ${TRACING}"
fi

# No DLQ on Lambda
DLQ=$(aws lambda get-function-configuration \
    --function-name "${STACK_NAME}-order-processor" \
    --region "${REGION}" \
    --query 'DeadLetterConfig.TargetArn' \
    --output text 2>/dev/null || echo "None")
if [ "${DLQ}" = "None" ] || [ -z "${DLQ}" ]; then
    check "Lambda DLQ not configured (intentional gap)" "PASS"
else
    check "Lambda DLQ not configured (intentional gap)" "DLQ exists: ${DLQ}"
fi

# No scaling policy on ASG
POLICY_COUNT=$(aws autoscaling describe-policies \
    --auto-scaling-group-name "${ASG_NAME}" \
    --region "${REGION}" \
    --query 'ScalingPolicies | length(@)' \
    --output text 2>/dev/null || echo "0")
if [ "${POLICY_COUNT}" = "0" ]; then
    check "ASG has no scaling policy (intentional gap)" "PASS"
else
    check "ASG has no scaling policy (intentional gap)" "${POLICY_COUNT} policies found"
fi

# 10. End-to-end order test
echo ""
echo "--- End-to-End Test ---"
RESPONSE=$(curl -s -X POST "${API_ENDPOINT}/orders" \
    -H "Content-Type: application/json" \
    -d '{"customerId":"test-validate","items":[{"productId":"PROD-001","quantity":1}],"totalAmount":79}' \
    --connect-timeout 5 --max-time 30 2>/dev/null || echo "{}")
if echo "${RESPONSE}" | grep -q "orderId"; then
    check "POST /orders returns orderId" "PASS"
else
    check "POST /orders returns orderId" "Response: ${RESPONSE}"
fi

# Summary
echo ""
echo "============================================"
echo "Results: ${PASS} passed, ${FAIL} failed"
echo "============================================"

if [ "${FAIL}" -gt 0 ]; then
    exit 1
fi
