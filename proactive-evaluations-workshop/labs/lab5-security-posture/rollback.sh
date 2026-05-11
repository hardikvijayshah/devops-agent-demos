#!/bin/bash
set -euo pipefail

# Lab 5 Rollback: No infrastructure changes to revert.
# Security gaps are baked into the CloudFormation template by design.

STACK_NAME="${1:-devops-eval}"
REGION="${AWS_REGION:-us-east-1}"

echo "============================================"
echo "Lab 5: Security Posture Gaps - Rollback"
echo "============================================"
echo ""
echo "Lab 5 does not modify infrastructure (gaps are by design)."
echo "No rollback needed."
echo ""
echo "Rollback complete. Ready for next lab."
