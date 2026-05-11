#!/bin/bash
set -euo pipefail

# Lab 4 Rollback: Restore original Lambda code

STACK_NAME="${1:-devops-eval}"
REGION="${AWS_REGION:-us-east-1}"

echo "============================================"
echo "Lab 4: Deployment Safety - Rollback"
echo "============================================"
echo ""

ORDER_FUNCTION=$(aws cloudformation describe-stacks \
    --stack-name "${STACK_NAME}" \
    --region "${REGION}" \
    --query 'Stacks[0].Outputs[?OutputKey==`OrderProcessorFunction`].OutputValue' \
    --output text)

echo "Restoring original order-processor code..."

TMPDIR=$(mktemp -d)
cat > "${TMPDIR}/index.py" << 'PYEOF'
import json
import os
import time
import uuid
import boto3
from decimal import Decimal

dynamodb = boto3.resource('dynamodb')
sns = boto3.client('sns')
orders_table = dynamodb.Table(os.environ['ORDERS_TABLE'])
inventory_table = dynamodb.Table(os.environ['INVENTORY_TABLE'])

def handler(event, context):
    body = json.loads(event.get('body', '{}'))
    order_id = str(uuid.uuid4())

    customer_id = body['customerId']
    items = body['items']
    total = body['totalAmount']

    orders_table.put_item(Item={
        'orderId': order_id,
        'customerId': customer_id,
        'items': items,
        'totalAmount': Decimal(str(total)),
        'status': 'RECEIVED',
        'createdAt': time.strftime('%Y-%m-%dT%H:%M:%SZ')
    })

    for item in items:
        result = inventory_table.scan(
            FilterExpression='productId = :pid',
            ExpressionAttributeValues={':pid': item['productId']}
        )
        if not result['Items']:
            return {
                'statusCode': 400,
                'body': json.dumps({'error': f'Product {item["productId"]} not found'})
            }

    orders_table.update_item(
        Key={'orderId': order_id},
        UpdateExpression='SET #s = :s',
        ExpressionAttributeNames={'#s': 'status'},
        ExpressionAttributeValues={':s': 'PROCESSING'}
    )

    sns.publish(
        TopicArn=os.environ['NOTIFICATION_TOPIC'],
        Message=json.dumps({'orderId': order_id, 'status': 'PROCESSING'}),
        Subject='Order Received'
    )

    return {
        'statusCode': 200,
        'headers': {'Content-Type': 'application/json'},
        'body': json.dumps({'orderId': order_id, 'status': 'PROCESSING'})
    }
PYEOF

cd "${TMPDIR}" && zip -q index.zip index.py

aws lambda update-function-code \
    --function-name "${ORDER_FUNCTION}" \
    --region "${REGION}" \
    --zip-file "fileb://${TMPDIR}/index.zip"

rm -rf "${TMPDIR}"

echo "Original code restored."
echo ""

# Wait for update to complete
aws lambda wait function-updated \
    --function-name "${ORDER_FUNCTION}" \
    --region "${REGION}" 2>/dev/null || sleep 5

echo "Rollback complete. Ready for next lab."
