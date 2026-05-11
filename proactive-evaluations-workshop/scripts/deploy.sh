#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TEMPLATE_FILE="${SCRIPT_DIR}/../cloudformation/evaluations-workshop.yaml"
STACK_NAME="${1:-devops-eval}"
REGION="${AWS_REGION:-us-east-1}"
ALARM_EMAIL="${2:-}"

echo "============================================"
echo "AWS DevOps Agent - Proactive Evaluations Workshop"
echo "============================================"
echo "Stack Name:  ${STACK_NAME}"
echo "Region:      ${REGION}"
echo "Template:    ${TEMPLATE_FILE}"
echo ""

if ! command -v aws &> /dev/null; then
    echo "ERROR: AWS CLI is not installed. Please install it first."
    exit 1
fi

aws sts get-caller-identity --region "${REGION}" > /dev/null 2>&1 || {
    echo "ERROR: AWS credentials not configured. Run 'aws configure' first."
    exit 1
}

echo "Validating CloudFormation template..."
aws cloudformation validate-template \
    --template-body "file://${TEMPLATE_FILE}" \
    --region "${REGION}" > /dev/null

echo "Template validation passed."
echo ""

PARAMS="ParameterKey=ResourcePrefix,ParameterValue=${STACK_NAME}"
if [ -n "${ALARM_EMAIL}" ]; then
    PARAMS="${PARAMS} ParameterKey=AlarmEmail,ParameterValue=${ALARM_EMAIL}"
fi

echo "Deploying CloudFormation stack (this may take 5-10 minutes)..."
aws cloudformation deploy \
    --template-file "${TEMPLATE_FILE}" \
    --stack-name "${STACK_NAME}" \
    --parameter-overrides ${PARAMS} \
    --capabilities CAPABILITY_NAMED_IAM \
    --region "${REGION}" \
    --tags devopsagent=true Workshop=proactive-evaluations

echo ""
echo "Stack deployment complete. Fetching outputs..."
echo ""

aws cloudformation describe-stacks \
    --stack-name "${STACK_NAME}" \
    --region "${REGION}" \
    --query 'Stacks[0].Outputs[*].[OutputKey,OutputValue]' \
    --output table

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

echo ""
echo "Waiting for ALB health checks to pass..."
for i in {1..20}; do
    HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" \
        "${ALB_ENDPOINT}/health" \
        --connect-timeout 5 --max-time 10 2>/dev/null || echo "000")

    if [ "${HTTP_CODE}" = "200" ]; then
        echo "ALB is healthy (HTTP 200)."
        break
    fi
    echo "  Waiting... (attempt ${i}/20, HTTP ${HTTP_CODE})"
    sleep 15
done

echo ""
echo "Testing API Gateway..."
HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" \
    "${API_ENDPOINT}/inventory" \
    --connect-timeout 5 --max-time 10 2>/dev/null || echo "000")
echo "API Gateway /inventory: HTTP ${HTTP_CODE}"

echo ""
echo "============================================"
echo "Deployment successful!"
echo ""
echo "Infrastructure deployed with INTENTIONAL gaps:"
echo "  - DynamoDB: No auto-scaling, no throttle alarms"
echo "  - Lambda: No DLQ, no reserved concurrency, no X-Ray"
echo "  - API Gateway: No throttling, no WAF, no caching"
echo "  - Auto Scaling: Fixed size, no scaling policies"
echo "  - Alarms: Only 3 (should have 10+), thresholds too lenient"
echo ""
echo "Next steps:"
echo "  1. Configure DevOps Agent Space (tag: devopsagent=true)"
echo "  2. Start Lab 1: cd ../labs/lab1-observability-gaps/"
echo "============================================"
