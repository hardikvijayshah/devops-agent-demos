#!/bin/bash
set -euo pipefail

STACK_NAME="${1:-devops-agent-cicd}"
REGION="${AWS_REGION:-us-east-1}"

echo "============================================"
echo "AWS DevOps Agent - CI/CD Pipeline Workshop Cleanup"
echo "============================================"
echo "Stack Name:  ${STACK_NAME}"
echo "Region:      ${REGION}"
echo ""

read -p "Are you sure you want to delete the stack '${STACK_NAME}'? (y/N): " confirm
if [[ "${confirm}" != "y" && "${confirm}" != "Y" ]]; then
    echo "Cleanup cancelled."
    exit 0
fi

BUCKET_NAME=$(aws cloudformation describe-stacks \
    --stack-name "${STACK_NAME}" \
    --region "${REGION}" \
    --query 'Stacks[0].Outputs[?OutputKey==`ArtifactBucketName`].OutputValue' \
    --output text 2>/dev/null || echo "")

if [ -n "${BUCKET_NAME}" ] && [ "${BUCKET_NAME}" != "None" ]; then
    echo "Emptying S3 bucket: ${BUCKET_NAME}..."
    aws s3 rm "s3://${BUCKET_NAME}" --recursive --region "${REGION}" 2>/dev/null || true

    echo "Removing versioned objects..."
    aws s3api list-object-versions \
        --bucket "${BUCKET_NAME}" \
        --region "${REGION}" \
        --query '{Objects: Versions[].{Key:Key,VersionId:VersionId}}' \
        --output json 2>/dev/null | \
    aws s3api delete-objects \
        --bucket "${BUCKET_NAME}" \
        --delete "$(cat -)" \
        --region "${REGION}" 2>/dev/null || true

    aws s3api list-object-versions \
        --bucket "${BUCKET_NAME}" \
        --region "${REGION}" \
        --query '{Objects: DeleteMarkers[].{Key:Key,VersionId:VersionId}}' \
        --output json 2>/dev/null | \
    aws s3api delete-objects \
        --bucket "${BUCKET_NAME}" \
        --delete "$(cat -)" \
        --region "${REGION}" 2>/dev/null || true
fi

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
