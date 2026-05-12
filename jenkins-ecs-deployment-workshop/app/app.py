from flask import Flask, jsonify, request
import time
import os
import socket
import logging

app = Flask(__name__)
start_time = time.time()

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


@app.route('/health')
def health():
    return jsonify({
        'status': 'healthy',
        'uptime': int(time.time() - start_time),
        'hostname': socket.gethostname(),
        'version': os.environ.get('APP_VERSION', '1.0.0'),
        'environment': os.environ.get('ENVIRONMENT', 'production')
    })


@app.route('/')
def index():
    return jsonify({
        'service': 'Jenkins ECS Deployment Workshop',
        'version': os.environ.get('APP_VERSION', '1.0.0'),
        'hostname': socket.gethostname(),
        'region': os.environ.get('AWS_REGION', 'us-east-1')
    })


@app.route('/api/status')
def status():
    return jsonify({
        'status': 'operational',
        'uptime': int(time.time() - start_time),
        'version': os.environ.get('APP_VERSION', '1.0.0'),
        'tasks_running': True
    })


@app.route('/api/process', methods=['POST'])
def process():
    data = request.get_json(silent=True) or {}
    logger.info(f"Processing request: {data}")
    return jsonify({
        'processed': True,
        'input': data,
        'hostname': socket.gethostname(),
        'timestamp': int(time.time())
    })


@app.route('/api/info')
def info():
    return jsonify({
        'app': 'devops-agent-jenkins-ecs',
        'version': os.environ.get('APP_VERSION', '1.0.0'),
        'build_number': os.environ.get('BUILD_NUMBER', 'local'),
        'commit_sha': os.environ.get('COMMIT_SHA', 'unknown'),
        'deploy_time': os.environ.get('DEPLOY_TIME', 'unknown')
    })


if __name__ == '__main__':
    app.run(host='0.0.0.0', port=8080)
