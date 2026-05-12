#!/bin/bash
set -euo pipefail

STACK_NAME="${1:-devops-agent-jenkins}"
REGION="${AWS_REGION:-us-east-1}"
REQUEST_COUNT="${2:-20}"
INTERVAL="${3:-2}"

ALB_ENDPOINT=$(aws cloudformation describe-stacks \
    --stack-name "${STACK_NAME}" \
    --region "${REGION}" \
    --query 'Stacks[0].Outputs[?OutputKey==`ALBEndpoint`].OutputValue' \
    --output text)

if [ -z "${ALB_ENDPOINT}" ] || [ "${ALB_ENDPOINT}" = "None" ]; then
    echo "ERROR: Could not retrieve ALB endpoint from stack '${STACK_NAME}'"
    exit 1
fi

echo "============================================"
echo "Generating Traffic to ECS Application"
echo "============================================"
echo "ALB Endpoint:  ${ALB_ENDPOINT}"
echo "Requests:      ${REQUEST_COUNT}"
echo "Interval:      ${INTERVAL}s between requests"
echo ""

ENDPOINTS=("/health" "/" "/api/status" "/api/process" "/api/info")
success_count=0
error_count=0

for i in $(seq 1 "${REQUEST_COUNT}"); do
    ENDPOINT=${ENDPOINTS[$((RANDOM % ${#ENDPOINTS[@]}))]}

    if [ "${ENDPOINT}" = "/api/process" ]; then
        echo -n "[${i}/${REQUEST_COUNT}] POST ${ENDPOINT}... "
        HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" \
            -X POST "${ALB_ENDPOINT}${ENDPOINT}" \
            -H "Content-Type: application/json" \
            -d '{"action":"test","id":'$i'}' \
            --connect-timeout 5 --max-time 15 2>/dev/null || echo "000")
    else
        echo -n "[${i}/${REQUEST_COUNT}] GET ${ENDPOINT}... "
        HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" \
            "${ALB_ENDPOINT}${ENDPOINT}" \
            --connect-timeout 5 --max-time 15 2>/dev/null || echo "000")
    fi

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
