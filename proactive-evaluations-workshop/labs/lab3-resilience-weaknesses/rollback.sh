#!/bin/bash
set -euo pipefail

# Lab 3 Rollback: No infrastructure changes to revert.
# Resilience gaps are in the application code by design.

STACK_NAME="${1:-devops-eval}"
REGION="${AWS_REGION:-us-east-1}"

echo "============================================"
echo "Lab 3: Application Resilience - Rollback"
echo "============================================"
echo ""
echo "Lab 3 does not modify infrastructure (gaps are by design)."
echo "No rollback needed."
echo ""
echo "Rollback complete. Ready for next lab."
