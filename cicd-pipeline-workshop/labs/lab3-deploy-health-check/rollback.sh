#!/bin/bash
set -euo pipefail

STACK_NAME="${1:-devops-agent-cicd}"
REGION="${AWS_REGION:-us-east-1}"

echo "============================================"
echo "Lab 3: Deploy Health Check - Rolling Back"
echo "============================================"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
"${SCRIPT_DIR}/../lab1-build-failure/rollback.sh" "${STACK_NAME}"
