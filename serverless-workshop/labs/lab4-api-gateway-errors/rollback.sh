#!/bin/bash
set -euo pipefail

STACK_NAME="${1:-devops-agent-serverless}"
REGION="${AWS_REGION:-us-east-1}"

FUNCTION_NAME=$(aws cloudformation describe-stacks \
    --stack-name "${STACK_NAME}" \
    --region "${REGION}" \
    --query 'Stacks[0].Outputs[?OutputKey==`OrderApiFunctionName`].OutputValue' \
    --output text)

ORDERS_TABLE=$(aws cloudformation describe-stacks \
    --stack-name "${STACK_NAME}" \
    --region "${REGION}" \
    --query 'Stacks[0].Outputs[?OutputKey==`OrdersTableName`].OutputValue' \
    --output text)

STATE_MACHINE_ARN=$(aws cloudformation describe-stacks \
    --stack-name "${STACK_NAME}" \
    --region "${REGION}" \
    --query 'Stacks[0].Outputs[?OutputKey==`StateMachineArn`].OutputValue' \
    --output text)

echo "============================================"
echo "Lab 4: API Gateway 5xx Errors - Rolling Back"
echo "============================================"

ORIGINAL_CODE=$(cat <<PYEOF
import json
import os
import uuid
import time
import boto3

sfn_client = boto3.client('stepfunctions')
dynamodb = boto3.resource('dynamodb')
orders_table = dynamodb.Table('${ORDERS_TABLE}')

def handler(event, context):
    try:
        body = json.loads(event.get('body', '{}'))

        order_id = str(uuid.uuid4())
        order = {
            'orderId': order_id,
            'customerId': body.get('customerId', 'anonymous'),
            'items': body.get('items', []),
            'totalAmount': body.get('totalAmount', 0),
            'status': 'RECEIVED',
            'createdAt': int(time.time())
        }

        orders_table.put_item(Item=order)

        sfn_client.start_execution(
            stateMachineArn='${STATE_MACHINE_ARN}',
            name=f'order-{order_id}',
            input=json.dumps(order)
        )

        return {
            'statusCode': 200,
            'headers': {'Content-Type': 'application/json'},
            'body': json.dumps({
                'message': 'Order received',
                'orderId': order_id,
                'status': 'RECEIVED'
            })
        }
    except Exception as e:
        print(f'Error processing order: {str(e)}')
        return {
            'statusCode': 500,
            'headers': {'Content-Type': 'application/json'},
            'body': json.dumps({'error': str(e)})
        }
PYEOF
)

TEMP_DIR=$(mktemp -d)
echo "${ORIGINAL_CODE}" > "${TEMP_DIR}/index.py"
cd "${TEMP_DIR}" && zip -q function.zip index.py

aws lambda update-function-code \
    --function-name "${FUNCTION_NAME}" \
    --zip-file "fileb://${TEMP_DIR}/function.zip" \
    --region "${REGION}" > /dev/null

aws lambda wait function-updated \
    --function-name "${FUNCTION_NAME}" \
    --region "${REGION}"

rm -rf "${TEMP_DIR}"

echo "Rollback complete. Original order-api code restored."
echo "============================================"
