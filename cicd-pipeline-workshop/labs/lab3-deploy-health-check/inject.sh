#!/bin/bash
set -euo pipefail

STACK_NAME="${1:-devops-agent-cicd}"
REGION="${AWS_REGION:-us-east-1}"

BUCKET_NAME=$(aws cloudformation describe-stacks \
    --stack-name "${STACK_NAME}" \
    --region "${REGION}" \
    --query 'Stacks[0].Outputs[?OutputKey==`ArtifactBucketName`].OutputValue' \
    --output text)

PIPELINE_NAME=$(aws cloudformation describe-stacks \
    --stack-name "${STACK_NAME}" \
    --region "${REGION}" \
    --query 'Stacks[0].Outputs[?OutputKey==`PipelineName`].OutputValue' \
    --output text)

echo "============================================"
echo "Lab 3: Deploy Health Check Failure - Injecting"
echo "============================================"

TEMP_DIR=$(mktemp -d)

cat > "${TEMP_DIR}/app.py" << 'EOF'
from flask import Flask, jsonify, request
import time
import os
import socket

app = Flask(__name__)
start_time = time.time()

@app.route('/health')
def health():
    return jsonify({
        'status': 'healthy',
        'uptime': time.time() - start_time,
        'hostname': socket.gethostname(),
        'version': os.environ.get('APP_VERSION', '1.1.0')
    })

@app.route('/')
def index():
    return jsonify({'service': 'CI/CD Workshop', 'version': '1.1.0'})

@app.route('/api/status')
def status():
    return jsonify({'status': 'operational'})

@app.route('/api/process', methods=['POST'])
def process():
    data = request.get_json(silent=True) or {}
    return jsonify({'processed': True, 'input': data})

if __name__ == '__main__':
    app.run(host='0.0.0.0', port=5000)
EOF

cat > "${TEMP_DIR}/requirements.txt" << 'EOF'
flask==3.1.1
gunicorn==23.0.0
EOF

cat > "${TEMP_DIR}/buildspec-build.yml" << 'EOF'
version: 0.2
phases:
  install:
    runtime-versions:
      python: 3.12
    commands:
      - pip install -r requirements.txt
  build:
    commands:
      - python -m py_compile app.py
      - echo "Build successful"
artifacts:
  files:
    - '**/*'
EOF

cat > "${TEMP_DIR}/buildspec-test.yml" << 'EOF'
version: 0.2
phases:
  install:
    runtime-versions:
      python: 3.12
    commands:
      - pip install -r requirements.txt
  build:
    commands:
      - python -m unittest discover -s tests -v
artifacts:
  files:
    - '**/*'
EOF

mkdir -p "${TEMP_DIR}/tests"
cat > "${TEMP_DIR}/tests/test_app.py" << 'EOF'
import unittest
import json
import sys
sys.path.insert(0, '.')
from app import app

class TestApp(unittest.TestCase):
    def setUp(self):
        self.client = app.test_client()

    def test_health(self):
        response = self.client.get('/health')
        self.assertEqual(response.status_code, 200)

if __name__ == '__main__':
    unittest.main()
EOF

cat > "${TEMP_DIR}/appspec.yml" << 'EOF'
version: 0.0
os: linux
files:
  - source: /
    destination: /opt/webapp
hooks:
  AfterInstall:
    - location: scripts/install_dependencies.sh
      timeout: 120
      runas: root
  ApplicationStart:
    - location: scripts/start_server_broken.sh
      timeout: 60
      runas: root
  ValidateService:
    - location: scripts/validate_service.sh
      timeout: 60
      runas: root
EOF

mkdir -p "${TEMP_DIR}/scripts"
cat > "${TEMP_DIR}/scripts/install_dependencies.sh" << 'EOF'
#!/bin/bash
set -e
cd /opt/webapp
pip3.12 install -r requirements.txt
EOF

cat > "${TEMP_DIR}/scripts/start_server_broken.sh" << 'EOF'
#!/bin/bash
set -e
pkill -f gunicorn || true
sleep 2
cd /opt/webapp
# Bug: wrong port (8080 instead of 5000) - ALB health check will fail
export APP_VERSION="1.1.0"
nohup gunicorn --bind 0.0.0.0:8080 --workers 2 --timeout 30 app:app > /var/log/webapp.log 2>&1 &
sleep 3
# Local check passes on 8080
curl -sf http://localhost:8080/health || exit 1
echo "Server started on port 8080"
EOF

cat > "${TEMP_DIR}/scripts/start_server.sh" << 'EOF'
#!/bin/bash
set -e
pkill -f gunicorn || true
sleep 2
cd /opt/webapp
export APP_VERSION="1.1.0"
nohup gunicorn --bind 0.0.0.0:5000 --workers 2 --timeout 30 app:app > /var/log/webapp.log 2>&1 &
sleep 3
curl -sf http://localhost:5000/health || exit 1
EOF

cat > "${TEMP_DIR}/scripts/validate_service.sh" << 'EOF'
#!/bin/bash
set -e
sleep 5
for i in {1..10}; do
    if curl -sf http://localhost:8080/health > /dev/null 2>&1; then
        exit 0
    fi
    sleep 3
done
exit 1
EOF

chmod +x "${TEMP_DIR}/scripts/"*.sh
cd "${TEMP_DIR}" && zip -r app.zip . > /dev/null

aws s3 cp "${TEMP_DIR}/app.zip" "s3://${BUCKET_NAME}/source/app.zip" \
    --region "${REGION}" > /dev/null

rm -rf "${TEMP_DIR}"

echo "Triggering pipeline..."
aws codepipeline start-pipeline-execution \
    --name "${PIPELINE_NAME}" \
    --region "${REGION}" > /dev/null

echo ""
echo "============================================"
echo "Failure injected!"
echo ""
echo "The appspec.yml now references 'start_server_broken.sh' which"
echo "starts the application on port 8080 instead of 5000."
echo "The ALB health check expects port 5000, so instances will"
echo "be marked unhealthy and CodeDeploy will trigger a rollback."
echo ""
echo "Next steps:"
echo "  1. Wait for pipeline to reach Deploy stage (~5 min)"
echo "  2. Watch CodeDeploy deployment fail and auto-rollback"
echo "  3. Observe DevOps Agent investigation"
echo ""
echo "To rollback: ./rollback.sh ${STACK_NAME}"
echo "============================================"
