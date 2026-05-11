#!/bin/bash
set -euo pipefail

STACK_NAME="${1:-devops-agent-cicd}"
REGION="${AWS_REGION:-us-east-1}"

CODEBUILD_ROLE_ARN=$(aws cloudformation describe-stacks \
    --stack-name "${STACK_NAME}" \
    --region "${REGION}" \
    --query 'Stacks[0].Outputs[?OutputKey==`CodeBuildRoleArn`].OutputValue' \
    --output text)

ROLE_NAME=$(echo "${CODEBUILD_ROLE_ARN}" | awk -F'/' '{print $NF}')

PIPELINE_NAME=$(aws cloudformation describe-stacks \
    --stack-name "${STACK_NAME}" \
    --region "${REGION}" \
    --query 'Stacks[0].Outputs[?OutputKey==`PipelineName`].OutputValue' \
    --output text)

echo "============================================"
echo "Lab 5: Pipeline Permission Issue - Injecting"
echo "============================================"
echo "CodeBuild Role: ${ROLE_NAME}"
echo ""

echo "Saving current inline policy..."
CURRENT_POLICY=$(aws iam get-role-policy \
    --role-name "${ROLE_NAME}" \
    --policy-name "CodeBuildPolicy" \
    --region "${REGION}" \
    --query 'PolicyDocument' \
    --output json)
echo "${CURRENT_POLICY}" > /tmp/lab5-original-policy.json

echo "Replacing CodeBuild S3 policy with restricted version..."
aws iam put-role-policy \
    --role-name "${ROLE_NAME}" \
    --policy-name "CodeBuildPolicy" \
    --policy-document '{
        "Version": "2012-10-17",
        "Statement": [
            {
                "Effect": "Allow",
                "Action": [
                    "logs:CreateLogGroup",
                    "logs:CreateLogStream",
                    "logs:PutLogEvents"
                ],
                "Resource": "*"
            },
            {
                "Effect": "Deny",
                "Action": [
                    "s3:GetObject",
                    "s3:PutObject"
                ],
                "Resource": "*"
            }
        ]
    }' \
    --region "${REGION}"

echo ""
echo "Triggering pipeline..."
aws codepipeline start-pipeline-execution \
    --name "${PIPELINE_NAME}" \
    --region "${REGION}" > /dev/null

echo ""
echo "============================================"
echo "Failure injected!"
echo ""
echo "The CodeBuild role now has an explicit DENY on S3 actions."
echo "The build stage will fail because CodeBuild cannot:"
echo "  - Download source artifacts from S3"
echo "  - Upload build artifacts to S3"
echo ""
echo "Next steps:"
echo "  1. Wait for Build stage to fail (~2 minutes)"
echo "  2. Observe DevOps Agent investigation"
echo ""
echo "Expected DevOps Agent findings:"
echo "  - AccessDenied errors in CodeBuild logs"
echo "  - IAM policy change detected on CodeBuild role"
echo "  - Recommendation to fix IAM permissions"
echo ""
echo "To rollback: ./rollback.sh ${STACK_NAME}"
echo "============================================"
