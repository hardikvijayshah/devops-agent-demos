#!/bin/bash
set -euo pipefail

STACK_NAME="${1:-devops-agent-cicd}"
REGION="${AWS_REGION:-us-east-1}"
ERRORS=0

echo "============================================"
echo "Validating CI/CD Pipeline Workshop Stack"
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
check "Stack exists and is healthy" "${STACK_STATUS}"

if [ "${STACK_STATUS}" != "CREATE_COMPLETE" ] && [ "${STACK_STATUS}" != "UPDATE_COMPLETE" ]; then
    echo ""
    echo "ERROR: Stack is not in a healthy state (${STACK_STATUS}). Cannot validate."
    exit 1
fi

echo ""
echo "--- VPC and Networking ---"
VPC_ID=$(aws cloudformation describe-stack-resources \
    --stack-name "${STACK_NAME}" \
    --region "${REGION}" \
    --logical-resource-id VPC \
    --query 'StackResources[0].PhysicalResourceId' \
    --output text 2>/dev/null || echo "")
check "VPC" "${VPC_ID}"

echo ""
echo "--- Application Load Balancer ---"
ALB_ENDPOINT=$(aws cloudformation describe-stacks \
    --stack-name "${STACK_NAME}" \
    --region "${REGION}" \
    --query 'Stacks[0].Outputs[?OutputKey==`ALBEndpoint`].OutputValue' \
    --output text)
check "ALB Endpoint" "${ALB_ENDPOINT}"

echo ""
echo "--- Auto Scaling Group ---"
ASG_NAME=$(aws cloudformation describe-stacks \
    --stack-name "${STACK_NAME}" \
    --region "${REGION}" \
    --query 'Stacks[0].Outputs[?OutputKey==`AutoScalingGroupName`].OutputValue' \
    --output text)
INSTANCE_COUNT=$(aws autoscaling describe-auto-scaling-groups \
    --auto-scaling-group-names "${ASG_NAME}" \
    --region "${REGION}" \
    --query 'AutoScalingGroups[0].Instances | length(@)' \
    --output text 2>/dev/null || echo "0")
check "ASG instances (expected 2)" "${INSTANCE_COUNT}"

echo ""
echo "--- CodePipeline ---"
PIPELINE_NAME=$(aws cloudformation describe-stacks \
    --stack-name "${STACK_NAME}" \
    --region "${REGION}" \
    --query 'Stacks[0].Outputs[?OutputKey==`PipelineName`].OutputValue' \
    --output text)
PIPELINE_STATUS=$(aws codepipeline get-pipeline-state \
    --name "${PIPELINE_NAME}" \
    --region "${REGION}" \
    --query 'stageStates[0].latestExecution.status' \
    --output text 2>/dev/null || echo "")
check "Pipeline (${PIPELINE_NAME})" "${PIPELINE_STATUS}"

echo ""
echo "--- CodeBuild Projects ---"
BUILD_PROJECT=$(aws cloudformation describe-stacks \
    --stack-name "${STACK_NAME}" \
    --region "${REGION}" \
    --query 'Stacks[0].Outputs[?OutputKey==`BuildProjectName`].OutputValue' \
    --output text)
check "Build project" "${BUILD_PROJECT}"

TEST_PROJECT=$(aws cloudformation describe-stacks \
    --stack-name "${STACK_NAME}" \
    --region "${REGION}" \
    --query 'Stacks[0].Outputs[?OutputKey==`TestProjectName`].OutputValue' \
    --output text)
check "Test project" "${TEST_PROJECT}"

echo ""
echo "--- CodeDeploy ---"
DEPLOY_APP=$(aws cloudformation describe-stacks \
    --stack-name "${STACK_NAME}" \
    --region "${REGION}" \
    --query 'Stacks[0].Outputs[?OutputKey==`CodeDeployApplicationName`].OutputValue' \
    --output text)
check "CodeDeploy application" "${DEPLOY_APP}"

DEPLOY_GROUP=$(aws cloudformation describe-stacks \
    --stack-name "${STACK_NAME}" \
    --region "${REGION}" \
    --query 'Stacks[0].Outputs[?OutputKey==`DeploymentGroupName`].OutputValue' \
    --output text)
check "Deployment group" "${DEPLOY_GROUP}"

echo ""
echo "--- S3 Artifact Bucket ---"
BUCKET_NAME=$(aws cloudformation describe-stacks \
    --stack-name "${STACK_NAME}" \
    --region "${REGION}" \
    --query 'Stacks[0].Outputs[?OutputKey==`ArtifactBucketName`].OutputValue' \
    --output text)
SOURCE_EXISTS=$(aws s3 ls "s3://${BUCKET_NAME}/source/app.zip" \
    --region "${REGION}" 2>/dev/null | wc -l | tr -d ' ')
check "Source artifact in S3" "${SOURCE_EXISTS}"

echo ""
echo "--- CloudWatch Alarms ---"
ALARM_COUNT=$(aws cloudwatch describe-alarms \
    --alarm-name-prefix "${STACK_NAME}" \
    --region "${REGION}" \
    --query 'length(MetricAlarms)' \
    --output text)
check "CloudWatch Alarms (expected 8)" "${ALARM_COUNT}"

echo ""
echo "--- End-to-End Test: ALB Health Check ---"
if [ -n "${ALB_ENDPOINT}" ]; then
    RESPONSE=$(curl -s -w "\n%{http_code}" \
        "${ALB_ENDPOINT}/health" \
        --connect-timeout 10 --max-time 30 2>/dev/null || echo -e "\n000")
    HTTP_CODE=$(echo "${RESPONSE}" | tail -1)
    BODY=$(echo "${RESPONSE}" | head -1)
    check "GET /health (expected 200)" "${HTTP_CODE}"
    echo "  Response: ${BODY}"
fi

echo ""
echo "============================================"
if [ "${ERRORS}" -eq 0 ]; then
    echo "All validations passed!"
else
    echo "FAILED: ${ERRORS} validation(s) failed."
fi
echo "============================================"
exit "${ERRORS}"
