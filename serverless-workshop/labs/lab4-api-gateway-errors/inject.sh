#!/bin/bash
set -euo pipefail

STACK_NAME="${1:-devops-agent-serverless}"
REGION="${AWS_REGION:-us-east-1}"

FUNCTION_NAME=$(aws cloudformation describe-stacks \
    --stack-name "${STACK_NAME}" \
    --region "${REGION}" \
    --query 'Stacks[0].Outputs[?OutputKey==`OrderApiFunctionName`].OutputValue' \
    --output text)

echo "============================================"
echo "Lab 4: API Gateway 5xx Errors - Injecting Failure"
echo "============================================"
echo "Function: ${FUNCTION_NAME}"
echo ""

echo "Deploying Lambda code that returns malformed responses..."
BROKEN_CODE=$(cat <<'PYEOF'
import json
import os
import uuid
import time

def handler(event, context):
    # Simulate malformed response - missing required 'statusCode' field
    # and returning a non-JSON body. API Gateway expects a specific
    # response format from Lambda proxy integrations.
    body = json.loads(event.get('body', '{}'))

    # Randomly alternate between different failure modes
    failure_mode = hash(str(time.time())) % 3

    if failure_mode == 0:
        # Missing statusCode - causes 502
        return {
            'body': json.dumps({'message': 'processed'})
        }
    elif failure_mode == 1:
        # Raise unhandled exception - causes 502
        raise RuntimeError('Unexpected internal error in order processing')
    else:
        # Return non-string body - causes 502
        return {
            'statusCode': 200,
            'body': {'message': 'this should be a string, not a dict'}
        }
PYEOF
)

TEMP_DIR=$(mktemp -d)
echo "${BROKEN_CODE}" > "${TEMP_DIR}/index.py"
cd "${TEMP_DIR}" && zip -q function.zip index.py

aws lambda update-function-code \
    --function-name "${FUNCTION_NAME}" \
    --zip-file "fileb://${TEMP_DIR}/function.zip" \
    --region "${REGION}" > /dev/null

aws lambda wait function-updated \
    --function-name "${FUNCTION_NAME}" \
    --region "${REGION}"

rm -rf "${TEMP_DIR}"

echo ""
echo "============================================"
echo "Failure injected!"
echo ""
echo "The order-api Lambda now returns malformed responses:"
echo "  - Missing statusCode field"
echo "  - Unhandled exceptions"
echo "  - Non-string body field"
echo ""
echo "API Gateway will return 502 Bad Gateway for all these cases."
echo ""
echo "Next steps:"
echo "  1. Generate traffic: ../../scripts/generate-traffic.sh ${STACK_NAME} 30 1"
echo "  2. Wait 2-3 minutes for API Gateway 5xx alarm"
echo "  3. Observe DevOps Agent investigation"
echo ""
echo "Expected DevOps Agent findings:"
echo "  - API Gateway 5XXError metric spike"
echo "  - Lambda execution errors and malformed responses"
echo "  - Code change detected as root cause"
echo ""
echo "To rollback: ./rollback.sh ${STACK_NAME}"
echo "============================================"
