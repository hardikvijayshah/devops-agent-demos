#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TEMPLATE_FILE="${SCRIPT_DIR}/../cloudformation/serverless-workshop.yaml"
STACK_NAME="${1:-devops-agent-serverless}"
REGION="${AWS_REGION:-us-east-1}"
ALARM_EMAIL="${2:-}"

echo "============================================"
echo "AWS DevOps Agent - Serverless Workshop Deploy"
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

echo "Deploying CloudFormation stack..."
aws cloudformation deploy \
    --template-file "${TEMPLATE_FILE}" \
    --stack-name "${STACK_NAME}" \
    --parameter-overrides ${PARAMS} \
    --capabilities CAPABILITY_NAMED_IAM \
    --region "${REGION}" \
    --tags devopsagent=true Workshop=serverless-troubleshooting

echo ""
echo "Stack deployment complete. Fetching outputs..."
echo ""

aws cloudformation describe-stacks \
    --stack-name "${STACK_NAME}" \
    --region "${REGION}" \
    --query 'Stacks[0].Outputs[*].[OutputKey,OutputValue]' \
    --output table

echo ""
echo "============================================"
echo "Deployment successful!"
echo ""
echo "Next steps:"
echo "  1. Configure your DevOps Agent Space to discover resources with tag: devopsagent=true"
echo "  2. Run the traffic generator: ./generate-traffic.sh"
echo "  3. Start Lab 1: cd ../labs/lab1-lambda-timeout/"
echo "============================================"
