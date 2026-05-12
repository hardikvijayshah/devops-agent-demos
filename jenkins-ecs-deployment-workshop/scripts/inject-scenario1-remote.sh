#!/bin/bash
set -e

ACCOUNT_ID=686588766535
REGION=us-east-1
ECR_REPO="${ACCOUNT_ID}.dkr.ecr.${REGION}.amazonaws.com/devops-agent-jenkins-app"

# Login to ECR
aws ecr get-login-password --region ${REGION} | docker login --username AWS --password-stdin ${ACCOUNT_ID}.dkr.ecr.${REGION}.amazonaws.com

# Create broken image
mkdir -p /tmp/broken-build

cat > /tmp/broken-build/app.py << 'EOF'
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

cat > /tmp/broken-build/Dockerfile << 'EOF'
FROM python:3.12-slim
WORKDIR /app
COPY app.py .
CMD ["python", "app.py"]
EOF

echo "Building BROKEN Docker image..."
docker build -t ${ECR_REPO}:broken -t ${ECR_REPO}:latest /tmp/broken-build/

echo "Pushing broken image to ECR..."
docker push ${ECR_REPO}:broken
docker push ${ECR_REPO}:latest

echo "BROKEN_IMAGE_PUSHED"
