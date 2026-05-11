#!/bin/bash
set -euo pipefail

# Lab 2 Rollback: No infrastructure changes to revert.
# Capacity gaps are baked into the CloudFormation template.

STACK_NAME="${1:-devops-eval}"
REGION="${AWS_REGION:-us-east-1}"

echo "============================================"
echo "Lab 2: Capacity Planning Gaps - Rollback"
echo "============================================"
echo ""
echo "Lab 2 does not modify infrastructure (gaps are by design)."
echo "No rollback needed."
echo ""
echo "Rollback complete. Ready for next lab."
