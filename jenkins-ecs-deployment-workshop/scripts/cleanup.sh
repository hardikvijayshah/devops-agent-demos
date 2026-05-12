#!/bin/bash
set -euo pipefail

STACK_NAME="${1:-devops-agent-jenkins}"
REGION="${AWS_REGION:-us-east-1}"

echo "============================================"
echo "AWS DevOps Agent - Jenkins ECS Workshop Cleanup"
echo "============================================"
echo "Stack Name:  ${STACK_NAME}"
echo "Region:      ${REGION}"
echo ""

read -p "Are you sure you want to delete ALL resources for '${STACK_NAME}'? (y/N): " confirm
if [[ "${confirm}" != "y" && "${confirm}" != "Y" ]]; then
    echo "Cleanup cancelled."
    exit 0
fi

# Delete all images from ECR (required before stack deletion)
echo "Deleting ECR images..."
IMAGE_IDS=$(aws ecr list-images \
    --repository-name "${STACK_NAME}-app" \
    --region "${REGION}" \
    --output json 2>/dev/null || echo '{"imageIds":[]}')

IMAGE_COUNT=$(echo "${IMAGE_IDS}" | jq '.imageIds | length')
if [ "${IMAGE_COUNT}" -gt 0 ]; then
    echo "${IMAGE_IDS}" | jq '{imageIds: .imageIds}' | \
        aws ecr batch-delete-image \
            --repository-name "${STACK_NAME}-app" \
            --region "${REGION}" \
            --cli-input-json "file:///dev/stdin" > /dev/null 2>&1 || true
    echo "  ECR images deleted (${IMAGE_COUNT} images)."
fi

# Scale down ECS service to 0 (speeds up stack deletion)
echo "Scaling down ECS service..."
aws ecs update-service \
    --cluster "${STACK_NAME}-cluster" \
    --service "${STACK_NAME}-service" \
    --desired-count 0 \
    --region "${REGION}" > /dev/null 2>&1 || true

sleep 10

# Delete SSM parameter
echo "Cleaning up SSM parameters..."
aws ssm delete-parameter \
    --name "/${STACK_NAME}/jenkins-initial-password" \
    --region "${REGION}" 2>/dev/null || true

# Delete CloudFormation stack
echo "Deleting CloudFormation stack..."
aws cloudformation delete-stack \
    --stack-name "${STACK_NAME}" \
    --region "${REGION}"

echo "Waiting for stack deletion to complete (this may take several minutes)..."
aws cloudformation wait stack-delete-complete \
    --stack-name "${STACK_NAME}" \
    --region "${REGION}"

echo ""
echo "============================================"
echo "Stack '${STACK_NAME}' has been deleted."
echo "============================================"
