#!/bin/bash
set -euo pipefail

STACK_NAME="${1:-devops-eval}"
DURATION="${2:-60}"
INTERVAL="${3:-2}"
REGION="${AWS_REGION:-us-east-1}"

API_ENDPOINT=$(aws cloudformation describe-stacks \
    --stack-name "${STACK_NAME}" \
    --region "${REGION}" \
    --query 'Stacks[0].Outputs[?OutputKey==`ApiEndpoint`].OutputValue' \
    --output text)

ALB_ENDPOINT=$(aws cloudformation describe-stacks \
    --stack-name "${STACK_NAME}" \
    --region "${REGION}" \
    --query 'Stacks[0].Outputs[?OutputKey==`ALBEndpoint`].OutputValue' \
    --output text)

echo "============================================"
echo "Traffic Generator: Proactive Evaluations Workshop"
echo "============================================"
echo "API Endpoint: ${API_ENDPOINT}"
echo "ALB Endpoint: ${ALB_ENDPOINT}"
echo "Duration:     ${DURATION} requests"
echo "Interval:     ${INTERVAL} seconds"
echo ""

PRODUCTS=("PROD-001" "PROD-002" "PROD-003" "PROD-004" "PROD-005" "PROD-006" "PROD-007" "PROD-008")
CUSTOMERS=("cust-001" "cust-002" "cust-003" "cust-004" "cust-005")

SUCCESS=0
ERRORS=0

for i in $(seq 1 "${DURATION}"); do
    CUSTOMER=${CUSTOMERS[$((RANDOM % ${#CUSTOMERS[@]}))]}
    PRODUCT=${PRODUCTS[$((RANDOM % ${#PRODUCTS[@]}))]}
    QTY=$((RANDOM % 5 + 1))
    AMOUNT=$((RANDOM % 200 + 10))

    # POST order
    HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" \
        -X POST "${API_ENDPOINT}/orders" \
        -H "Content-Type: application/json" \
        -d "{\"customerId\":\"${CUSTOMER}\",\"items\":[{\"productId\":\"${PRODUCT}\",\"quantity\":${QTY}}],\"totalAmount\":${AMOUNT}}" \
        --connect-timeout 5 --max-time 30 2>/dev/null || echo "000")

    if [ "${HTTP_CODE}" = "200" ] || [ "${HTTP_CODE}" = "201" ]; then
        SUCCESS=$((SUCCESS + 1))
    else
        ERRORS=$((ERRORS + 1))
    fi

    # GET inventory (every 3rd request)
    if [ $((i % 3)) -eq 0 ]; then
        curl -s -o /dev/null "${API_ENDPOINT}/inventory" \
            --connect-timeout 5 --max-time 30 2>/dev/null || true
    fi

    # GET ALB health (every 5th request)
    if [ $((i % 5)) -eq 0 ]; then
        curl -s -o /dev/null "${ALB_ENDPOINT}/health" \
            --connect-timeout 5 --max-time 10 2>/dev/null || true
    fi

    printf "  [%d/%d] POST /orders -> HTTP %s (success: %d, errors: %d)\n" \
        "$i" "${DURATION}" "${HTTP_CODE}" "${SUCCESS}" "${ERRORS}"

    sleep "${INTERVAL}"
done

echo ""
echo "============================================"
echo "Traffic generation complete."
echo "  Total requests: ${DURATION}"
echo "  Successful:     ${SUCCESS}"
echo "  Errors:         ${ERRORS}"
echo "============================================"
