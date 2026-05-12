#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
STACK_NAME="${1:-devops-agent-jenkins}"
REGION="${AWS_REGION:-us-east-1}"

ACCOUNT_ID=$(aws sts get-caller-identity --query 'Account' --output text)
ECR_REPO="${ACCOUNT_ID}.dkr.ecr.${REGION}.amazonaws.com/${STACK_NAME}-app"

echo "============================================"
echo "Building and Pushing Initial Docker Image"
echo "============================================"
echo "ECR Repo: ${ECR_REPO}"
echo ""

# Login to ECR
echo "Logging into ECR..."
aws ecr get-login-password --region "${REGION}" | \
    docker login --username AWS --password-stdin "${ACCOUNT_ID}.dkr.ecr.${REGION}.amazonaws.com"

# Build the image
echo "Building Docker image..."
docker build \
    --build-arg APP_VERSION=1.0.0 \
    --build-arg BUILD_NUMBER=initial \
    --build-arg COMMIT_SHA=initial-deploy \
    -t "${ECR_REPO}:latest" \
    -t "${ECR_REPO}:1" \
    "${SCRIPT_DIR}/../app/"

# Push to ECR
echo "Pushing image to ECR..."
docker push "${ECR_REPO}:latest"
docker push "${ECR_REPO}:1"

echo ""
echo "Initial image pushed successfully."

# Scale up and force new deployment to pick up the image
echo "Triggering ECS service deployment (desired count: 2)..."
aws ecs update-service \
    --cluster "${STACK_NAME}-cluster" \
    --service "${STACK_NAME}-service" \
    --desired-count 2 \
    --force-new-deployment \
    --region "${REGION}" > /dev/null

echo "ECS deployment triggered."
echo "============================================"
