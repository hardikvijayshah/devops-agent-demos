#!/bin/bash
set -euo pipefail

STACK_NAME="${1:-devops-agent-jenkins}"
REGION="${AWS_REGION:-us-east-1}"

ACCOUNT_ID=$(aws sts get-caller-identity --query 'Account' --output text)
ECR_REPO="${ACCOUNT_ID}.dkr.ecr.${REGION}.amazonaws.com/${STACK_NAME}-app"
CLUSTER_NAME="${STACK_NAME}-cluster"
SERVICE_NAME="${STACK_NAME}-service"

echo "============================================"
echo "Scenario 3: Resource Limits (OOM Kill)"
echo "============================================"
echo ""
echo "This simulates a deployment where the application has a"
echo "memory leak. The container exceeds its memory limit and"
echo "gets OOM-killed by the container runtime."
echo ""

# Build an image with memory leak
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
import threading

app = Flask(__name__)
start_time = time.time()
memory_hog = []

def leak_memory():
    """Gradually consume memory until OOM kill."""
    global memory_hog
    time.sleep(45)  # Pass initial health checks first
    while True:
        # Allocate ~10MB per second
        memory_hog.append(' ' * 10_000_000)
        time.sleep(1)

# Start memory leak in background
leak_thread = threading.Thread(target=leak_memory, daemon=True)
leak_thread.start()

@app.route('/health')
def health():
    mem_used_mb = len(memory_hog) * 10
    return jsonify({
        'status': 'healthy',
        'uptime': int(time.time() - start_time),
        'hostname': socket.gethostname(),
        'memory_consumed_mb': mem_used_mb
    })

@app.route('/')
def index():
    return jsonify({
        'service': 'Jenkins ECS Workshop (MEMORY LEAK)',
        'version': '3.0.0-leak'
    })

@app.route('/api/status')
def status():
    mem_used_mb = len(memory_hog) * 10
    return jsonify({
        'status': 'operational',
        'memory_mb': mem_used_mb,
        'warning': 'memory growing' if mem_used_mb > 100 else None
    })

if __name__ == '__main__':
    app.run(host='0.0.0.0', port=8080)
EOF

echo "Building image with memory leak..."
aws ecr get-login-password --region "${REGION}" | \
    docker login --username AWS --password-stdin "${ACCOUNT_ID}.dkr.ecr.${REGION}.amazonaws.com"

docker build -t "${ECR_REPO}:oom" -t "${ECR_REPO}:latest" "${TEMP_DIR}"
docker push "${ECR_REPO}:oom"
docker push "${ECR_REPO}:latest"

rm -rf "${TEMP_DIR}"

echo ""
echo "Deploying image with memory leak to ECS..."

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
    jq --arg IMAGE "${ECR_REPO}:oom" \
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
echo "  - App starts normally and passes all health checks"
echo "  - After 45 seconds, a background thread allocates ~10MB/sec"
echo "  - Task memory limit is 512MB, so OOM kill in ~45-50 seconds"
echo "  - Total time to crash: ~90 seconds after start"
echo ""
echo "What to observe:"
echo "  1. Tasks deploy and pass initial health checks"
echo "  2. After ~90 seconds, tasks get OOM-killed"
echo "  3. ECS task stopped reason: 'OutOfMemoryError'"
echo "  4. CloudWatch alarm: ${STACK_NAME}-ecs-memory-high fires"
echo "  5. CloudWatch alarm: ${STACK_NAME}-ecs-running-tasks fires"
echo "  6. Tasks restart and crash again (crash loop)"
echo "  7. ECS circuit breaker triggers rollback"
echo ""
echo "Monitor memory:"
echo "  aws ecs describe-tasks --cluster ${CLUSTER_NAME} --tasks \$(aws ecs list-tasks --cluster ${CLUSTER_NAME} --service-name ${SERVICE_NAME} --query 'taskArns[0]' --output text) --query 'tasks[0].{Status:lastStatus,StopCode:stopCode,Reason:stoppedReason}' --output table"
echo ""
echo "Expected DevOps Agent findings:"
echo "  - Tasks killed with OutOfMemoryError"
echo "  - Memory utilization metric spike to 100%"
echo "  - Container logs showing memory growth"
echo "  - Correlation with image change"
echo "  - Recommendation: Fix memory leak, or increase task memory limit"
echo ""
echo "To rollback: ./rollback.sh ${STACK_NAME}"
echo "============================================"
