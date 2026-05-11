#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TEMPLATE_FILE="${SCRIPT_DIR}/../cloudformation/cicd-workshop.yaml"
STACK_NAME="${1:-devops-agent-cicd}"
REGION="${AWS_REGION:-us-east-1}"
ALARM_EMAIL="${2:-}"

echo "============================================"
echo "AWS DevOps Agent - CI/CD Pipeline Workshop Deploy"
echo "============================================"
echo "Stack Name:  ${STACK_NAME}"
echo "Region:      ${REGION}"
echo "Template:    ${TEMPLATE_FILE}"
echo ""

if ! command -v aws &> /dev/null; then
    echo "ERROR: AWS CLI is not installed. Please install it first."
    exit 1
fi

aws sts get-caller-identity --region "${REGION}" > /dev/null 2>&1 || {
    echo "ERROR: AWS credentials not configured. Run 'aws configure' first."
    exit 1
}

echo "Validating CloudFormation template..."
aws cloudformation validate-template \
    --template-body "file://${TEMPLATE_FILE}" \
    --region "${REGION}" > /dev/null

echo "Template validation passed."
echo ""

PARAMS="ParameterKey=ResourcePrefix,ParameterValue=${STACK_NAME}"
if [ -n "${ALARM_EMAIL}" ]; then
    PARAMS="${PARAMS} ParameterKey=AlarmEmail,ParameterValue=${ALARM_EMAIL}"
fi

echo "Deploying CloudFormation stack (this may take 10-15 minutes)..."
aws cloudformation deploy \
    --template-file "${TEMPLATE_FILE}" \
    --stack-name "${STACK_NAME}" \
    --parameter-overrides ${PARAMS} \
    --capabilities CAPABILITY_NAMED_IAM \
    --region "${REGION}" \
    --tags devopsagent=true Workshop=cicd-pipeline

echo ""
echo "Stack deployment complete. Fetching outputs..."
echo ""

aws cloudformation describe-stacks \
    --stack-name "${STACK_NAME}" \
    --region "${REGION}" \
    --query 'Stacks[0].Outputs[*].[OutputKey,OutputValue]' \
    --output table

ALB_ENDPOINT=$(aws cloudformation describe-stacks \
    --stack-name "${STACK_NAME}" \
    --region "${REGION}" \
    --query 'Stacks[0].Outputs[?OutputKey==`ALBEndpoint`].OutputValue' \
    --output text)

echo ""
echo "Waiting for EC2 instances to become healthy..."
for i in {1..30}; do
    HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" \
        "${ALB_ENDPOINT}/health" \
        --connect-timeout 5 --max-time 10 2>/dev/null || echo "000")

    if [ "${HTTP_CODE}" = "200" ]; then
        echo "Instances are healthy (HTTP 200 from /health)."
        break
    fi
    echo "  Waiting... (attempt ${i}/30, HTTP ${HTTP_CODE})"
    sleep 20
done

echo ""
echo "Triggering initial pipeline execution..."
BUCKET_NAME=$(aws cloudformation describe-stacks \
    --stack-name "${STACK_NAME}" \
    --region "${REGION}" \
    --query 'Stacks[0].Outputs[?OutputKey==`ArtifactBucketName`].OutputValue' \
    --output text)

PIPELINE_NAME=$(aws cloudformation describe-stacks \
    --stack-name "${STACK_NAME}" \
    --region "${REGION}" \
    --query 'Stacks[0].Outputs[?OutputKey==`PipelineName`].OutputValue' \
    --output text)

aws codepipeline start-pipeline-execution \
    --name "${PIPELINE_NAME}" \
    --region "${REGION}" > /dev/null 2>&1 || true

echo ""
echo "============================================"
echo "Deployment successful!"
echo ""
echo "Next steps:"
echo "  1. Configure your DevOps Agent Space to discover resources with tag: devopsagent=true"
echo "  2. Wait for the initial pipeline execution to complete (~5 min)"
echo "  3. Start Lab 1: cd ../labs/lab1-build-failure/"
echo "============================================"
