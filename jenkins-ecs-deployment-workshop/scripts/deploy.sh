#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TEMPLATE_FILE="${SCRIPT_DIR}/../cloudformation/jenkins-ecs-workshop.yaml"
STACK_NAME="${1:-devops-agent-jenkins}"
REGION="${AWS_REGION:-us-east-1}"
ALARM_EMAIL="${2:-}"

echo "============================================"
echo "AWS DevOps Agent - Jenkins + ECS Workshop"
echo "============================================"
echo "Stack Name:  ${STACK_NAME}"
echo "Region:      ${REGION}"
echo "Template:    ${TEMPLATE_FILE}"
echo ""

# Validate prerequisites
if ! command -v aws &> /dev/null; then
    echo "ERROR: AWS CLI is not installed. Please install it first."
    exit 1
fi

if ! command -v docker &> /dev/null; then
    echo "ERROR: Docker is required to build and push the initial image."
    exit 1
fi

if ! command -v jq &> /dev/null; then
    echo "ERROR: jq is required. Install it: https://jqlang.github.io/jq/download/"
    exit 1
fi

aws sts get-caller-identity --region "${REGION}" > /dev/null 2>&1 || {
    echo "ERROR: AWS credentials not configured. Run 'aws configure' first."
    exit 1
}

ACCOUNT_ID=$(aws sts get-caller-identity --query 'Account' --output text)
echo "AWS Account: ${ACCOUNT_ID}"
echo ""

# Validate template
echo "Validating CloudFormation template..."
aws cloudformation validate-template \
    --template-body "file://${TEMPLATE_FILE}" \
    --region "${REGION}" > /dev/null
echo "Template validation passed."
echo ""

# Build parameters
PARAMS="ParameterKey=ResourcePrefix,ParameterValue=${STACK_NAME}"
if [ -n "${ALARM_EMAIL}" ]; then
    PARAMS="${PARAMS} ParameterKey=AlarmEmail,ParameterValue=${ALARM_EMAIL}"
fi

# Deploy stack
echo "Deploying CloudFormation stack (this may take 10-15 minutes)..."
aws cloudformation deploy \
    --template-file "${TEMPLATE_FILE}" \
    --stack-name "${STACK_NAME}" \
    --parameter-overrides ${PARAMS} \
    --capabilities CAPABILITY_NAMED_IAM \
    --region "${REGION}" \
    --tags devopsagent=true Workshop=jenkins-ecs-deployment

echo ""
echo "Stack deployment complete. Fetching outputs..."
echo ""

aws cloudformation describe-stacks \
    --stack-name "${STACK_NAME}" \
    --region "${REGION}" \
    --query 'Stacks[0].Outputs[*].[OutputKey,OutputValue]' \
    --output table

# Get outputs
ECR_REPO=$(aws cloudformation describe-stacks \
    --stack-name "${STACK_NAME}" \
    --region "${REGION}" \
    --query 'Stacks[0].Outputs[?OutputKey==`ECRRepositoryUri`].OutputValue' \
    --output text)

JENKINS_URL=$(aws cloudformation describe-stacks \
    --stack-name "${STACK_NAME}" \
    --region "${REGION}" \
    --query 'Stacks[0].Outputs[?OutputKey==`JenkinsURL`].OutputValue' \
    --output text)

ALB_ENDPOINT=$(aws cloudformation describe-stacks \
    --stack-name "${STACK_NAME}" \
    --region "${REGION}" \
    --query 'Stacks[0].Outputs[?OutputKey==`ALBEndpoint`].OutputValue' \
    --output text)

echo ""
echo "============================================"
echo "Building and pushing initial Docker image..."
echo "============================================"

# Build and push initial image
"${SCRIPT_DIR}/deploy-initial-image.sh" "${STACK_NAME}"

echo ""
echo "Waiting for ECS service to stabilize with new image..."
aws ecs wait services-stable \
    --cluster "${STACK_NAME}-cluster" \
    --services "${STACK_NAME}-service" \
    --region "${REGION}" 2>/dev/null || {
    echo "  Service stabilization timed out. Checking status..."
    aws ecs describe-services \
        --cluster "${STACK_NAME}-cluster" \
        --services "${STACK_NAME}-service" \
        --region "${REGION}" \
        --query 'services[0].{Status:status,Running:runningCount,Desired:desiredCount}' \
        --output table
}

# Verify ALB health
echo ""
echo "Verifying application health via ALB..."
for i in {1..20}; do
    HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" \
        "${ALB_ENDPOINT}/health" \
        --connect-timeout 5 --max-time 10 2>/dev/null || echo "000")

    if [ "${HTTP_CODE}" = "200" ]; then
        echo "Application is healthy (HTTP 200)."
        break
    fi
    echo "  Waiting... (attempt ${i}/20, HTTP ${HTTP_CODE})"
    sleep 15
done

echo ""
echo "============================================"
echo "Deployment successful!"
echo "============================================"
echo ""
echo "Endpoints:"
echo "  Application (ALB):  ${ALB_ENDPOINT}"
echo "  Jenkins:            ${JENKINS_URL}"
echo ""
echo "Jenkins Initial Password:"
echo "  aws ssm get-parameter --name '/${STACK_NAME}/jenkins-initial-password' --with-decryption --query 'Parameter.Value' --output text --region ${REGION}"
echo ""
echo "Next steps:"
echo "  1. Access Jenkins at ${JENKINS_URL}"
echo "  2. Complete Jenkins setup wizard"
echo "  3. Configure the pipeline job (see jenkins/ folder)"
echo "  4. Run scenarios from the scenarios/ folder"
echo "  5. Configure DevOps Agent Space with tag: devopsagent=true"
echo "============================================"
