#!/bin/bash
set -euo pipefail

# Lab 4: Deployment Safety Gaps
# Demonstrates DevOps Agent identifying missing deployment safeguards:
# - No deployment rollback mechanism
# - No canary/progressive deployment
# - No pre-deployment validation
# - No deployment alarms
# This lab simulates a bad deployment to highlight missing safety nets.

STACK_NAME="${1:-devops-eval}"
REGION="${AWS_REGION:-us-east-1}"

echo "============================================"
echo "Lab 4: Deployment Safety Gaps - Inject"
echo "============================================"
echo ""

ORDER_FUNCTION=$(aws cloudformation describe-stacks \
    --stack-name "${STACK_NAME}" \
    --region "${REGION}" \
    --query 'Stacks[0].Outputs[?OutputKey==`OrderProcessorFunction`].OutputValue' \
    --output text)

API_ENDPOINT=$(aws cloudformation describe-stacks \
    --stack-name "${STACK_NAME}" \
    --region "${REGION}" \
    --query 'Stacks[0].Outputs[?OutputKey==`ApiEndpoint`].OutputValue' \
    --output text)

echo "Step 1: Deploying a 'bad' Lambda version (simulating unsafe deploy)..."
echo ""

# Save current configuration for rollback
aws lambda get-function \
    --function-name "${ORDER_FUNCTION}" \
    --region "${REGION}" \
    --query 'Configuration.{Memory:MemorySize,Timeout:Timeout,Runtime:Runtime}' \
    --output table

echo ""
echo "  Deploying broken code (simulates no pre-deploy validation)..."

# Deploy code with a subtle bug (incorrect DynamoDB key schema)
aws lambda update-function-code \
    --function-name "${ORDER_FUNCTION}" \
    --region "${REGION}" \
    --zip-file fileb://<(python3 -c "
import zipfile, io
buf = io.BytesIO()
with zipfile.ZipFile(buf, 'w') as zf:
    zf.writestr('index.py', '''
import json
import os
import time
import uuid
import boto3
from decimal import Decimal

dynamodb = boto3.resource(\"dynamodb\")
sns = boto3.client(\"sns\")
orders_table = dynamodb.Table(os.environ[\"ORDERS_TABLE\"])
inventory_table = dynamodb.Table(os.environ[\"INVENTORY_TABLE\"])

def handler(event, context):
    body = json.loads(event.get(\"body\", \"{}\"))
    order_id = str(uuid.uuid4())

    customer_id = body.get(\"customerId\", \"unknown\")
    items = body.get(\"items\", [])
    total = body.get(\"totalAmount\", 0)

    # BUG: Wrong key name (ordId instead of orderId)
    orders_table.put_item(Item={
        \"ordId\": order_id,  # Wrong! Should be orderId
        \"customerId\": customer_id,
        \"items\": items,
        \"totalAmount\": Decimal(str(total)),
        \"status\": \"RECEIVED\",
        \"createdAt\": time.strftime(\"%Y-%m-%dT%H:%M:%SZ\")
    })

    return {
        \"statusCode\": 200,
        \"headers\": {\"Content-Type\": \"application/json\"},
        \"body\": json.dumps({\"orderId\": order_id, \"status\": \"PROCESSING\"})
    }
''')
buf.seek(0)
import sys
sys.stdout.buffer.write(buf.read())
") 2>/dev/null || {
    # Fallback if python3 not available - use a temp file
    TMPDIR=$(mktemp -d)
    cat > "${TMPDIR}/index.py" << 'PYEOF'
import json
import os
import time
import uuid
import boto3
from decimal import Decimal

dynamodb = boto3.resource("dynamodb")
sns = boto3.client("sns")
orders_table = dynamodb.Table(os.environ["ORDERS_TABLE"])
inventory_table = dynamodb.Table(os.environ["INVENTORY_TABLE"])

def handler(event, context):
    body = json.loads(event.get("body", "{}"))
    order_id = str(uuid.uuid4())

    customer_id = body.get("customerId", "unknown")
    items = body.get("items", [])
    total = body.get("totalAmount", 0)

    # BUG: Wrong key name (ordId instead of orderId)
    orders_table.put_item(Item={
        "ordId": order_id,
        "customerId": customer_id,
        "items": items,
        "totalAmount": Decimal(str(total)),
        "status": "RECEIVED",
        "createdAt": time.strftime("%Y-%m-%dT%H:%M:%SZ")
    })

    return {
        "statusCode": 200,
        "headers": {"Content-Type": "application/json"},
        "body": json.dumps({"orderId": order_id, "status": "PROCESSING"})
    }
PYEOF
    cd "${TMPDIR}" && zip -q index.zip index.py
    aws lambda update-function-code \
        --function-name "${ORDER_FUNCTION}" \
        --region "${REGION}" \
        --zip-file "fileb://${TMPDIR}/index.zip"
    rm -rf "${TMPDIR}"
}

echo "  Bad code deployed. No rollback mechanism exists!"
echo ""

echo "Step 2: Generating traffic against bad deployment..."
echo ""

SUCCESS=0
ERRORS=0
for i in $(seq 1 10); do
    HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" \
        -X POST "${API_ENDPOINT}/orders" \
        -H "Content-Type: application/json" \
        -d "{\"customerId\":\"deploy-test-${i}\",\"items\":[{\"productId\":\"PROD-001\",\"quantity\":1}],\"totalAmount\":79}" \
        --connect-timeout 5 --max-time 30 2>/dev/null || echo "000")

    if [ "${HTTP_CODE}" = "200" ]; then
        SUCCESS=$((SUCCESS + 1))
    else
        ERRORS=$((ERRORS + 1))
    fi
    sleep 1
done

echo "  Results: ${SUCCESS} success, ${ERRORS} errors"
echo "  (May appear to succeed but data is corrupted - wrong key schema)"

echo ""
echo "Step 3: Checking deployment safety configuration..."
echo ""

echo "  Lambda aliases/versions:"
aws lambda list-aliases \
    --function-name "${ORDER_FUNCTION}" \
    --region "${REGION}" \
    --query 'Aliases[*].Name' \
    --output text 2>/dev/null || echo "  (none - no versioning)"

echo ""
echo "  CodeDeploy for Lambda:"
echo "  (none configured - no progressive deployment)"

echo ""
echo "============================================"
echo "Lab 4 Setup Complete"
echo ""
echo "DEPLOYMENT SAFETY GAPS for DevOps Agent to discover:"
echo ""
echo "  MISSING SAFEGUARDS:"
echo "    - No Lambda versioning/aliases (can't rollback)"
echo "    - No CodeDeploy canary/linear deployment"
echo "    - No pre-deployment validation (smoke tests)"
echo "    - No deployment alarm (auto-rollback on errors)"
echo "    - No traffic shifting (all-at-once deployment)"
echo ""
echo "  CURRENT RISK:"
echo "    - Bad code deployed to 100% of traffic instantly"
echo "    - No way to automatically rollback"
echo "    - Data corruption happening silently"
echo ""
echo "EVALUATION PROMPT for DevOps Agent:"
echo "  'Evaluate deployment safety for Lambda functions tagged"
echo "   devopsagent=true. Check for rollback mechanisms,"
echo "   progressive deployment, and pre-deployment validation.'"
echo "============================================"
