#!/bin/bash
set -e

ACCOUNT_ID=686588766535
REGION=us-east-1
ECR_REPO="${ACCOUNT_ID}.dkr.ecr.${REGION}.amazonaws.com/devops-agent-jenkins-app"

# Login to ECR
aws ecr get-login-password --region ${REGION} | docker login --username AWS --password-stdin ${ACCOUNT_ID}.dkr.ecr.${REGION}.amazonaws.com

# Create build directory
mkdir -p /tmp/app-build

# Write requirements.txt
cat > /tmp/app-build/requirements.txt << 'EOF'
flask==3.0.0
gunicorn==21.2.0
EOF

# Write app.py
cat > /tmp/app-build/app.py << 'PYEOF'
from flask import Flask, jsonify, request
import time, os, socket, logging

app = Flask(__name__)
start_time = time.time()
logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

@app.route("/health")
def health():
    return jsonify({"status": "healthy", "uptime": int(time.time() - start_time), "hostname": socket.gethostname(), "version": os.environ.get("APP_VERSION", "1.0.0"), "environment": os.environ.get("ENVIRONMENT", "production")})

@app.route("/")
def index():
    return jsonify({"service": "Jenkins ECS Deployment Workshop", "version": os.environ.get("APP_VERSION", "1.0.0"), "hostname": socket.gethostname(), "region": os.environ.get("AWS_REGION", "us-east-1")})

@app.route("/api/status")
def status():
    return jsonify({"status": "operational", "uptime": int(time.time() - start_time), "version": os.environ.get("APP_VERSION", "1.0.0"), "tasks_running": True})

@app.route("/api/process", methods=["POST"])
def process():
    data = request.get_json(silent=True) or {}
    logger.info(f"Processing request: {data}")
    return jsonify({"processed": True, "input": data, "hostname": socket.gethostname(), "timestamp": int(time.time())})

@app.route("/api/info")
def info():
    return jsonify({"app": "devops-agent-jenkins-ecs", "version": os.environ.get("APP_VERSION", "1.0.0"), "build_number": os.environ.get("BUILD_NUMBER", "local"), "commit_sha": os.environ.get("COMMIT_SHA", "unknown"), "deploy_time": os.environ.get("DEPLOY_TIME", "unknown")})

if __name__ == "__main__":
    app.run(host="0.0.0.0", port=8080)
PYEOF

# Write Dockerfile
cat > /tmp/app-build/Dockerfile << 'DEOF'
FROM python:3.12-slim
WORKDIR /app
RUN apt-get update && apt-get install -y --no-install-recommends curl && rm -rf /var/lib/apt/lists/*
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt
COPY app.py .
ARG APP_VERSION=1.0.0
ARG BUILD_NUMBER=local
ARG COMMIT_SHA=unknown
ENV APP_VERSION=${APP_VERSION}
ENV BUILD_NUMBER=${BUILD_NUMBER}
ENV COMMIT_SHA=${COMMIT_SHA}
ENV DEPLOY_TIME=""
EXPOSE 8080
HEALTHCHECK --interval=15s --timeout=5s --start-period=10s --retries=3 CMD curl -f http://localhost:8080/health || exit 1
CMD ["gunicorn", "--bind", "0.0.0.0:8080", "--workers", "2", "--timeout", "30", "--access-logfile", "-", "app:app"]
DEOF

# Build image
echo "Building Docker image..."
docker build --build-arg APP_VERSION=1.0.0 --build-arg BUILD_NUMBER=initial --build-arg COMMIT_SHA=initial-deploy -t ${ECR_REPO}:latest -t ${ECR_REPO}:1 /tmp/app-build/

# Push to ECR
echo "Pushing to ECR..."
docker push ${ECR_REPO}:latest
docker push ${ECR_REPO}:1

echo "IMAGE_PUSH_COMPLETE"
