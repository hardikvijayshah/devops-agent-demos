#!/bin/bash
set -euo pipefail

STACK_NAME="${1:-devops-agent-serverless}"
REGION="${AWS_REGION:-us-east-1}"
REQUEST_COUNT="${2:-20}"
INTERVAL="${3:-2}"

API_ENDPOINT=$(aws cloudformation describe-stacks \
    --stack-name "${STACK_NAME}" \
    --region "${REGION}" \
    --query 'Stacks[0].Outputs[?OutputKey==`ApiEndpoint`].OutputValue' \
    --output text)

if [ -z "${API_ENDPOINT}" ]; then
    echo "ERROR: Could not retrieve API endpoint from stack '${STACK_NAME}'"
    exit 1
fi

echo "============================================"
echo "Generating Traffic to Order API"
echo "============================================"
echo "API Endpoint:  ${API_ENDPOINT}"
echo "Requests:      ${REQUEST_COUNT}"
echo "Interval:      ${INTERVAL}s between requests"
echo ""

PRODUCTS=("PROD-001" "PROD-002" "PROD-003" "PROD-004" "PROD-005")
CUSTOMERS=("CUST-001" "CUST-002" "CUST-003" "CUST-004" "CUST-005")

success_count=0
error_count=0

for i in $(seq 1 "${REQUEST_COUNT}"); do
    PRODUCT=${PRODUCTS[$((RANDOM % ${#PRODUCTS[@]}))]}
    CUSTOMER=${CUSTOMERS[$((RANDOM % ${#CUSTOMERS[@]}))]}
    QUANTITY=$((RANDOM % 3 + 1))
    AMOUNT=$((RANDOM % 200 + 10))

    PAYLOAD=$(cat <<EOF
{
  "customerId": "${CUSTOMER}",
  "items": [
    {
      "productId": "${PRODUCT}",
      "quantity": ${QUANTITY},
      "price": ${AMOUNT}
    }
  ],
  "totalAmount": ${AMOUNT}
}
EOF
)

    echo -n "[${i}/${REQUEST_COUNT}] Sending order for ${CUSTOMER} -> ${PRODUCT} (qty: ${QUANTITY})... "

    HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" \
        -X POST "${API_ENDPOINT}" \
        -H "Content-Type: application/json" \
        -d "${PAYLOAD}" \
        --connect-timeout 10 \
        --max-time 30 2>/dev/null || echo "000")

    if [ "${HTTP_CODE}" -ge 200 ] && [ "${HTTP_CODE}" -lt 300 ]; then
        echo "OK (${HTTP_CODE})"
        ((success_count++))
    else
        echo "FAILED (${HTTP_CODE})"
        ((error_count++))
    fi

    if [ "${i}" -lt "${REQUEST_COUNT}" ]; then
        sleep "${INTERVAL}"
    fi
done

echo ""
echo "============================================"
echo "Traffic Generation Complete"
echo "  Successful: ${success_count}"
echo "  Failed:     ${error_count}"
echo "  Total:      ${REQUEST_COUNT}"
echo "============================================"
