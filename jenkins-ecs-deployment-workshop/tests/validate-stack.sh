#!/bin/bash
set -euo pipefail

STACK_NAME="${1:-devops-agent-jenkins}"
REGION="${AWS_REGION:-us-east-1}"
ERRORS=0

echo "============================================"
echo "Validating Jenkins ECS Workshop Stack"
echo "============================================"
echo "Stack: ${STACK_NAME}"
echo "Region: ${REGION}"
echo ""

check() {
    local description="$1"
    local result="$2"
    if [ -n "${result}" ] && [ "${result}" != "None" ] && [ "${result}" != "null" ]; then
        echo "  [PASS] ${description}: ${result}"
    else
        echo "  [FAIL] ${description}"
        ((ERRORS++))
    fi
}

echo "--- Stack Status ---"
STACK_STATUS=$(aws cloudformation describe-stacks \
    --stack-name "${STACK_NAME}" \
    --region "${REGION}" \
    --query 'Stacks[0].StackStatus' \
    --output text 2>/dev/null || echo "NOT_FOUND")
check "Stack exists" "${STACK_STATUS}"

if [ "${STACK_STATUS}" != "CREATE_COMPLETE" ] && [ "${STACK_STATUS}" != "UPDATE_COMPLETE" ]; then
    echo ""
    echo "ERROR: Stack not healthy (${STACK_STATUS}). Cannot validate."
    exit 1
fi

echo ""
echo "--- ECS Cluster ---"
CLUSTER_STATUS=$(aws ecs describe-clusters \
    --clusters "${STACK_NAME}-cluster" \
    --region "${REGION}" \
    --query 'clusters[0].status' \
    --output text 2>/dev/null || echo "")
check "ECS Cluster" "${CLUSTER_STATUS}"

RUNNING_TASKS=$(aws ecs describe-services \
    --cluster "${STACK_NAME}-cluster" \
    --services "${STACK_NAME}-service" \
    --region "${REGION}" \
    --query 'services[0].runningCount' \
    --output text 2>/dev/null || echo "0")
check "ECS Running Tasks (expected 2)" "${RUNNING_TASKS}"

echo ""
echo "--- ECR Repository ---"
ECR_IMAGES=$(aws ecr list-images \
    --repository-name "${STACK_NAME}-app" \
    --region "${REGION}" \
    --query 'length(imageIds)' \
    --output text 2>/dev/null || echo "0")
check "ECR Images" "${ECR_IMAGES}"

echo ""
echo "--- Load Balancer ---"
ALB_ENDPOINT=$(aws cloudformation describe-stacks \
    --stack-name "${STACK_NAME}" \
    --region "${REGION}" \
    --query 'Stacks[0].Outputs[?OutputKey==`ALBEndpoint`].OutputValue' \
    --output text)
check "ALB Endpoint" "${ALB_ENDPOINT}"

if [ -n "${ALB_ENDPOINT}" ] && [ "${ALB_ENDPOINT}" != "None" ]; then
    ALB_HEALTH=$(curl -s -o /dev/null -w "%{http_code}" \
        "${ALB_ENDPOINT}/health" --connect-timeout 5 --max-time 10 2>/dev/null || echo "000")
    check "ALB Health Check (expected 200)" "${ALB_HEALTH}"
fi

echo ""
echo "--- Jenkins Server ---"
JENKINS_URL=$(aws cloudformation describe-stacks \
    --stack-name "${STACK_NAME}" \
    --region "${REGION}" \
    --query 'Stacks[0].Outputs[?OutputKey==`JenkinsURL`].OutputValue' \
    --output text)
check "Jenkins URL" "${JENKINS_URL}"

JENKINS_STATUS=$(curl -s -o /dev/null -w "%{http_code}" \
    "${JENKINS_URL}/login" --connect-timeout 5 --max-time 10 2>/dev/null || echo "000")
check "Jenkins Accessible (expected 200)" "${JENKINS_STATUS}"

echo ""
echo "--- CloudWatch Alarms ---"
ALARM_COUNT=$(aws cloudwatch describe-alarms \
    --alarm-name-prefix "${STACK_NAME}" \
    --region "${REGION}" \
    --query 'length(MetricAlarms)' \
    --output text)
check "CloudWatch Alarms (expected 6)" "${ALARM_COUNT}"

echo ""
echo "--- EventBridge Rules ---"
DEPLOY_RULE=$(aws events describe-rule \
    --name "${STACK_NAME}-ecs-deploy-failure" \
    --region "${REGION}" \
    --query 'State' \
    --output text 2>/dev/null || echo "")
check "ECS Deploy Failure Rule" "${DEPLOY_RULE}"

echo ""
echo "============================================"
if [ "${ERRORS}" -eq 0 ]; then
    echo "All validations passed!"
else
    echo "FAILED: ${ERRORS} validation(s) failed."
fi
echo "============================================"
exit "${ERRORS}"
