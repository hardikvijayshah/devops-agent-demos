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
echo "Lab 1: Build Failure - Rolling Back"
echo "============================================"

TEMP_DIR=$(mktemp -d)

cat > "${TEMP_DIR}/app.py" << 'APPEOF'
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
        'version': os.environ.get('APP_VERSION', '1.0.0')
    })

@app.route('/')
def index():
    return jsonify({
        'service': 'DevOps Agent CI/CD Workshop',
        'version': os.environ.get('APP_VERSION', '1.0.0'),
        'hostname': socket.gethostname()
    })

@app.route('/api/status')
def status():
    return jsonify({
        'status': 'operational',
        'uptime': time.time() - start_time,
        'version': os.environ.get('APP_VERSION', '1.0.0')
    })

@app.route('/api/process', methods=['POST'])
def process():
    data = request.get_json(silent=True) or {}
    return jsonify({
        'processed': True,
        'input': data,
        'hostname': socket.gethostname()
    })

if __name__ == '__main__':
    app.run(host='0.0.0.0', port=5000)
APPEOF

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
      - echo "Building application..."
      - python -m py_compile app.py
      - echo "Build successful"
  post_build:
    commands:
      - echo "Build completed on $(date)"
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
      - echo "Running tests..."
      - python -m pytest tests/ -v --tb=short 2>/dev/null || python -m unittest discover -s tests -v
      - echo "All tests passed"
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
        data = json.loads(response.data)
        self.assertEqual(data['status'], 'healthy')

    def test_index(self):
        response = self.client.get('/')
        self.assertEqual(response.status_code, 200)

    def test_status(self):
        response = self.client.get('/api/status')
        self.assertEqual(response.status_code, 200)

    def test_process(self):
        response = self.client.post('/api/process',
            data=json.dumps({'key': 'value'}),
            content_type='application/json')
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
    - location: scripts/start_server.sh
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

cat > "${TEMP_DIR}/scripts/start_server.sh" << 'EOF'
#!/bin/bash
set -e
pkill -f gunicorn || true
sleep 2
cd /opt/webapp
export APP_VERSION="1.0.0"
nohup gunicorn --bind 0.0.0.0:5000 --workers 2 --timeout 30 app:app > /var/log/webapp.log 2>&1 &
sleep 3
curl -sf http://localhost:5000/health || exit 1
echo "Server started successfully"
EOF

cat > "${TEMP_DIR}/scripts/validate_service.sh" << 'EOF'
#!/bin/bash
set -e
sleep 5
for i in {1..10}; do
    if curl -sf http://localhost:5000/health > /dev/null 2>&1; then
        echo "Service validation passed (attempt $i)"
        exit 0
    fi
    echo "Waiting for service... (attempt $i)"
    sleep 3
done
echo "Service validation failed"
exit 1
EOF

chmod +x "${TEMP_DIR}/scripts/"*.sh

cd "${TEMP_DIR}" && zip -r app.zip . > /dev/null

aws s3 cp "${TEMP_DIR}/app.zip" "s3://${BUCKET_NAME}/source/app.zip" \
    --region "${REGION}" > /dev/null

rm -rf "${TEMP_DIR}"

echo "Triggering pipeline with fixed source..."
aws codepipeline start-pipeline-execution \
    --name "${PIPELINE_NAME}" \
    --region "${REGION}" > /dev/null

echo "Rollback complete. Original source code restored and pipeline triggered."
echo "============================================"
