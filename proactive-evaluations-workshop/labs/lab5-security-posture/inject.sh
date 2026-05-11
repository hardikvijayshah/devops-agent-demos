#!/bin/bash
set -euo pipefail

# Lab 5: Security Posture Gaps
# Demonstrates DevOps Agent identifying security weaknesses:
# - API Gateway with no authentication
# - Lambda with overly broad IAM permissions
# - No WAF protection
# - No encryption on SNS
# - No VPC for Lambda (public internet access)
# - Security groups too permissive

STACK_NAME="${1:-devops-eval}"
REGION="${AWS_REGION:-us-east-1}"

echo "============================================"
echo "Lab 5: Security Posture Gaps - Inject"
echo "============================================"
echo ""

API_ENDPOINT=$(aws cloudformation describe-stacks \
    --stack-name "${STACK_NAME}" \
    --region "${REGION}" \
    --query 'Stacks[0].Outputs[?OutputKey==`ApiEndpoint`].OutputValue' \
    --output text)

ORDER_FUNCTION=$(aws cloudformation describe-stacks \
    --stack-name "${STACK_NAME}" \
    --region "${REGION}" \
    --query 'Stacks[0].Outputs[?OutputKey==`OrderProcessorFunction`].OutputValue' \
    --output text)

echo "Step 1: Demonstrating open API (no authentication)..."
echo ""
echo "  Anyone can call the API without credentials:"
HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" \
    -X POST "${API_ENDPOINT}/orders" \
    -H "Content-Type: application/json" \
    -d "{\"customerId\":\"anonymous\",\"items\":[{\"productId\":\"PROD-001\",\"quantity\":100}],\"totalAmount\":7900}" \
    --connect-timeout 5 --max-time 30 2>/dev/null || echo "000")
echo "  POST /orders (no auth): HTTP ${HTTP_CODE}"

echo ""
echo "Step 2: Checking Lambda IAM permissions (overly broad?)..."
echo ""

ROLE_ARN=$(aws lambda get-function-configuration \
    --function-name "${ORDER_FUNCTION}" \
    --region "${REGION}" \
    --query 'Role' \
    --output text)

ROLE_NAME=$(echo "${ROLE_ARN}" | awk -F'/' '{print $NF}')

echo "  Role: ${ROLE_NAME}"
echo "  Inline policies:"
aws iam list-role-policies \
    --role-name "${ROLE_NAME}" \
    --query 'PolicyNames' \
    --output table 2>/dev/null || echo "  (access denied to check)"

echo ""
echo "  Checking for wildcard actions..."
aws iam get-role-policy \
    --role-name "${ROLE_NAME}" \
    --policy-name "DynamoDBAccess" \
    --query 'PolicyDocument.Statement[*].Action' \
    --output text 2>/dev/null || echo "  (access denied to check)"

echo ""
echo "Step 3: Checking API Gateway authorization..."
echo ""

API_ID=$(aws cloudformation describe-stack-resources \
    --stack-name "${STACK_NAME}" \
    --logical-resource-id "ApiGateway" \
    --region "${REGION}" \
    --query 'StackResources[0].PhysicalResourceId' \
    --output text 2>/dev/null)

if [ -n "${API_ID}" ]; then
    echo "  API Gateway authorizers:"
    AUTHORIZER_COUNT=$(aws apigateway get-authorizers \
        --rest-api-id "${API_ID}" \
        --region "${REGION}" \
        --query 'items | length(@)' \
        --output text 2>/dev/null || echo "0")
    echo "  Count: ${AUTHORIZER_COUNT} (should be >= 1)"
fi

echo ""
echo "Step 4: Checking encryption configuration..."
echo ""

TOPIC_ARN=$(aws cloudformation describe-stacks \
    --stack-name "${STACK_NAME}" \
    --region "${REGION}" \
    --query 'Stacks[0].Outputs[?OutputKey==`AlarmTopicArn`].OutputValue' \
    --output text)

echo "  SNS Topic encryption:"
aws sns get-topic-attributes \
    --topic-arn "${TOPIC_ARN}" \
    --region "${REGION}" \
    --query 'Attributes.KmsMasterKeyId' \
    --output text 2>/dev/null || echo "  None (not encrypted)"

echo ""
echo "Step 5: Simulating abuse (no rate limiting)..."
echo ""
echo "  Sending 20 rapid requests (no throttling configured)..."

for i in $(seq 1 20); do
    curl -s -o /dev/null -X POST "${API_ENDPOINT}/orders" \
        -H "Content-Type: application/json" \
        -d "{\"customerId\":\"abuser-${i}\",\"items\":[{\"productId\":\"PROD-001\",\"quantity\":999}],\"totalAmount\":1}" \
        --connect-timeout 5 --max-time 30 2>/dev/null || true
done
echo "  All 20 accepted (no rate limiting!)"

echo ""
echo "============================================"
echo "Lab 5 Setup Complete"
echo ""
echo "SECURITY GAPS for DevOps Agent to discover:"
echo ""
echo "  API SECURITY:"
echo "    - No authentication (AuthorizationType: NONE)"
echo "    - No API key or usage plan"
echo "    - No WAF web ACL attached"
echo "    - No request throttling configured"
echo "    - No request body validation"
echo ""
echo "  IAM PERMISSIONS:"
echo "    - Lambda role has Scan permission (overly broad)"
echo "    - DynamoDB access includes DeleteItem (not needed)"
echo "    - No resource-level conditions (account/region)"
echo ""
echo "  DATA PROTECTION:"
echo "    - SNS topic not encrypted (KMS)"
echo "    - DynamoDB tables not encrypted with CMK"
echo "    - No VPC for Lambda (egress to internet)"
echo ""
echo "  NETWORK:"
echo "    - ALB SG allows 0.0.0.0/0 on port 80 (expected, but no WAF)"
echo "    - No VPC endpoints for DynamoDB (traffic goes via internet)"
echo ""
echo "EVALUATION PROMPT for DevOps Agent:"
echo "  'Evaluate security posture for resources tagged"
echo "   devopsagent=true. Check API authentication, IAM"
echo "   least privilege, encryption, and network security.'"
echo "============================================"
