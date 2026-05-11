#!/bin/bash
set -euo pipefail

STACK_NAME="${1:-devops-agent-cicd}"
REGION="${AWS_REGION:-us-east-1}"

echo "============================================"
echo "Lab 2: Test Failure - Rolling Back"
echo "============================================"

# Reuse Lab 1's rollback which restores the original working source
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
"${SCRIPT_DIR}/../lab1-build-failure/rollback.sh" "${STACK_NAME}"
