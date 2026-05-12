#!/bin/bash
set -euo pipefail

STACK_NAME="${1:-devops-agent-jenkins}"
REGION="${AWS_REGION:-us-east-1}"

ACCOUNT_ID=$(aws sts get-caller-identity --query 'Account' --output text)
ECR_REPO="${ACCOUNT_ID}.dkr.ecr.${REGION}.amazonaws.com/${STACK_NAME}-app"
CLUSTER_NAME="${STACK_NAME}-cluster"
SERVICE_NAME="${STACK_NAME}-service"

echo "============================================"
echo "Scenario 2: Health Check Failure Deployment"
echo "============================================"
echo ""
echo "This simulates a deployment where the application starts"
echo "successfully but the /health endpoint returns errors."
echo "The ALB health check fails, causing tasks to be deregistered."
echo ""

# Build an image with broken health check
TEMP_DIR=$(mktemp -d)
cat > "${TEMP_DIR}/Dockerfile" << 'EOF'
FROM python:3.12-slim
WORKDIR /app
RUN apt-get update && apt-get install -y --no-install-recommends curl && rm -rf /var/lib/apt/lists/*
RUN pip install --no-cache-dir flask gunicorn
COPY app.py .
EXPOSE 8080
CMD ["gunicorn", "--bind", "0.0.0.0:8080", "--workers", "2", "--timeout", "30", "app:app"]
EOF

cat > "${TEMP_DIR}/app.py" << 'EOF'
from flask import Flask, jsonify
import time
import socket

app = Flask(__name__)
start_time = time.time()

@app.route('/health')
def health():
    # Broken: returns 503 after startup grace period
    # Simulates a dependency that becomes unavailable
    uptime = time.time() - start_time
    if uptime > 30:
        return jsonify({
            'status': 'unhealthy',
            'error': 'Database connection pool exhausted',
            'uptime': int(uptime)
        }), 503
    return jsonify({'status': 'starting', 'uptime': int(uptime)}), 200

@app.route('/')
def index():
    return jsonify({
        'service': 'Jenkins ECS Workshop (BROKEN)',
        'version': '2.0.0-broken',
        'hostname': socket.gethostname()
    })

@app.route('/api/status')
def status():
    return jsonify({'status': 'degraded', 'reason': 'health check failing'})

if __name__ == '__main__':
    app.run(host='0.0.0.0', port=8080)
EOF

echo "Building image with broken health check..."
aws ecr get-login-password --region "${REGION}" | \
    docker login --username AWS --password-stdin "${ACCOUNT_ID}.dkr.ecr.${REGION}.amazonaws.com"

docker build -t "${ECR_REPO}:health-fail" -t "${ECR_REPO}:latest" "${TEMP_DIR}"
docker push "${ECR_REPO}:health-fail"
docker push "${ECR_REPO}:latest"

rm -rf "${TEMP_DIR}"

echo ""
echo "Deploying image with broken health check..."

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
    jq --arg IMAGE "${ECR_REPO}:health-fail" \
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
echo "  - App starts normally and passes initial health checks"
echo "  - After 30 seconds, /health starts returning HTTP 503"
echo "  - ALB marks targets as unhealthy"
echo "  - New tasks fail ALB health checks and get deregistered"
echo "  - ECS circuit breaker triggers rollback"
echo ""
echo "What to observe:"
echo "  1. Tasks start successfully (pass container health check initially)"
echo "  2. After ~45s, ALB health checks start failing"
echo "  3. CloudWatch alarm: ${STACK_NAME}-alb-unhealthy fires"
echo "  4. ECS deployment circuit breaker triggers rollback"
echo "  5. DevOps Agent investigates the failure pattern"
echo ""
echo "Monitor:"
echo "  watch -n 5 'aws elbv2 describe-target-health --target-group-arn \$(aws elbv2 describe-target-groups --names ${STACK_NAME}-tg --query \"TargetGroups[0].TargetGroupArn\" --output text) --output table'"
echo ""
echo "Expected DevOps Agent findings:"
echo "  - Health check returning 503 with 'Database connection pool exhausted'"
echo "  - Pattern: initial health passes then degrades (delayed failure)"
echo "  - ECS task logs showing the 503 responses"
echo "  - Recommendation: Fix dependency health check, add circuit breaker"
echo ""
echo "To rollback: ./rollback.sh ${STACK_NAME}"
echo "============================================"
