#!/bin/bash
set -euo pipefail

STACK_NAME="${1:-devops-agent-jenkins}"
REGION="${AWS_REGION:-us-east-1}"

ACCOUNT_ID=$(aws sts get-caller-identity --query 'Account' --output text)
ECR_REPO="${ACCOUNT_ID}.dkr.ecr.${REGION}.amazonaws.com/${STACK_NAME}-app"
CLUSTER_NAME="${STACK_NAME}-cluster"
SERVICE_NAME="${STACK_NAME}-service"

echo "============================================"
echo "Scenario 1: Bad Docker Image Deployment"
echo "============================================"
echo ""
echo "This simulates a Jenkins build that produces a crashing"
echo "Docker image. The container starts but immediately exits"
echo "because the application has a fatal import error."
echo ""

# Build a broken image
TEMP_DIR=$(mktemp -d)
cat > "${TEMP_DIR}/Dockerfile" << 'EOF'
FROM python:3.12-slim
WORKDIR /app
COPY app.py .
# Missing requirements install - flask not available
CMD ["python", "app.py"]
EOF

cat > "${TEMP_DIR}/app.py" << 'EOF'
# This will crash on import because flask is not installed
from flask import Flask
import nonexistent_module  # This guarantees a crash

app = Flask(__name__)

@app.route('/health')
def health():
    return "ok"

if __name__ == '__main__':
    app.run(host='0.0.0.0', port=8080)
EOF

echo "Building broken Docker image..."
aws ecr get-login-password --region "${REGION}" | \
    docker login --username AWS --password-stdin "${ACCOUNT_ID}.dkr.ecr.${REGION}.amazonaws.com"

docker build -t "${ECR_REPO}:broken" -t "${ECR_REPO}:latest" "${TEMP_DIR}"
docker push "${ECR_REPO}:broken"
docker push "${ECR_REPO}:latest"

rm -rf "${TEMP_DIR}"

echo ""
echo "Deploying broken image to ECS..."

# Get current task definition and update image
TASK_DEF_ARN=$(aws ecs describe-services \
    --cluster "${CLUSTER_NAME}" \
    --services "${SERVICE_NAME}" \
    --region "${REGION}" \
    --query 'services[0].taskDefinition' \
    --output text)

TASK_DEF=$(aws ecs describe-task-definition \
    --task-definition "${TASK_DEF_ARN}" \
    --region "${REGION}" \
    --query 'taskDefinition' | \
    jq --arg IMAGE "${ECR_REPO}:broken" \
    '.containerDefinitions[0].image = $IMAGE' | \
    jq 'del(.taskDefinitionArn, .revision, .status, .requiresAttributes, .compatibilities, .registeredAt, .registeredBy)')

NEW_TASK_ARN=$(echo "${TASK_DEF}" | \
    aws ecs register-task-definition \
        --region "${REGION}" \
        --cli-input-json "file:///dev/stdin" \
        --query 'taskDefinition.taskDefinitionArn' \
        --output text)

aws ecs update-service \
    --cluster "${CLUSTER_NAME}" \
    --service "${SERVICE_NAME}" \
    --task-definition "${NEW_TASK_ARN}" \
    --force-new-deployment \
    --region "${REGION}" > /dev/null

echo ""
echo "============================================"
echo "Failure injected!"
echo ""
echo "What happened:"
echo "  - A Docker image with a fatal import error was pushed to ECR"
echo "  - ECS service was updated to use the broken image"
echo "  - Containers will crash on startup (ImportError)"
echo "  - ECS deployment circuit breaker will detect the failure"
echo "  - Auto-rollback will revert to the previous working image"
echo ""
echo "What to observe:"
echo "  1. ECS tasks entering STOPPED state within 30-60 seconds"
echo "  2. CloudWatch alarm: ${STACK_NAME}-ecs-running-tasks fires"
echo "  3. CloudWatch alarm: ${STACK_NAME}-alb-unhealthy fires"
echo "  4. EventBridge triggers: ECS Deployment State Change (FAILED)"
echo "  5. DevOps Agent receives notification and investigates"
echo ""
echo "Monitor deployment:"
echo "  aws ecs describe-services --cluster ${CLUSTER_NAME} --services ${SERVICE_NAME} --query 'services[0].events[0:5]' --output table"
echo ""
echo "Expected DevOps Agent findings:"
echo "  - Container crash: ModuleNotFoundError in ECS task logs"
echo "  - Image change: broken tag deployed (correlates with failure)"
echo "  - Recommendation: Rollback to previous working image tag"
echo ""
echo "To manually rollback: ./rollback.sh ${STACK_NAME}"
echo "============================================"
