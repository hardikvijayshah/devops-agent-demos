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
