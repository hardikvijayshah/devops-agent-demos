#!/bin/bash
set -euo pipefail

# Lab 1 Rollback: No infrastructure changes to revert.
# The gaps are baked into the CloudFormation template by design.
# This script just confirms the environment is in its base state.

STACK_NAME="${1:-devops-eval}"
REGION="${AWS_REGION:-us-east-1}"

echo "============================================"
echo "Lab 1: Observability Gaps - Rollback"
echo "============================================"
echo ""
echo "Lab 1 does not modify infrastructure (gaps are by design)."
echo "No rollback needed."
echo ""
echo "Current alarm state:"
aws cloudwatch describe-alarms \
    --alarm-name-prefix "${STACK_NAME}" \
    --region "${REGION}" \
    --query 'MetricAlarms[*].[AlarmName,StateValue]' \
    --output table

echo ""
echo "Rollback complete. Ready for next lab."
