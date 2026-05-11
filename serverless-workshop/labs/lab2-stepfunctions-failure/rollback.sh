#!/bin/bash
set -euo pipefail

STACK_NAME="${1:-devops-agent-serverless}"
REGION="${AWS_REGION:-us-east-1}"

FUNCTION_NAME=$(aws cloudformation describe-stacks \
    --stack-name "${STACK_NAME}" \
    --region "${REGION}" \
    --query 'Stacks[0].Outputs[?OutputKey==`ValidateOrderFunctionName`].OutputValue' \
    --output text)

INVENTORY_TABLE=$(aws cloudformation describe-stacks \
    --stack-name "${STACK_NAME}" \
    --region "${REGION}" \
    --query 'Stacks[0].Outputs[?OutputKey==`InventoryTableName`].OutputValue' \
    --output text)

echo "============================================"
echo "Lab 2: Step Functions Failure - Rolling Back"
echo "============================================"

ORIGINAL_CODE=$(cat <<PYEOF
import json
import os
import boto3

dynamodb = boto3.resource('dynamodb')
inventory_table = dynamodb.Table('${INVENTORY_TABLE}')

def handler(event, context):
    order = event
    items = order.get('items', [])

    if not items:
        raise ValueError('Order must contain at least one item')

    if order.get('totalAmount', 0) <= 0:
        raise ValueError('Order total must be greater than zero')

    for item in items:
        product_id = item.get('productId')
        quantity = item.get('quantity', 0)

        response = inventory_table.get_item(Key={'productId': product_id})
        product = response.get('Item')

        if not product:
            raise ValueError(f'Product {product_id} not found')

        if int(product.get('stockCount', 0)) < quantity:
            raise ValueError(f'Insufficient stock for product {product_id}')

    return {
        **order,
        'validated': True
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

echo "Rollback complete. Original validation code restored."
echo "============================================"
