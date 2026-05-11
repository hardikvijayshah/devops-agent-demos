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

BUCKET_NAME=$(aws cloudformation describe-stacks \
    --stack-name "${STACK_NAME}" \
    --region "${REGION}" \
    --query 'Stacks[0].Outputs[?OutputKey==`ArtifactBucketName`].OutputValue' \
    --output text)

echo "============================================"
echo "Lab 5: Pipeline Permission - Rolling Back"
echo "============================================"

echo "Restoring original CodeBuild IAM policy..."
aws iam put-role-policy \
    --role-name "${ROLE_NAME}" \
    --policy-name "CodeBuildPolicy" \
    --policy-document "{
        \"Version\": \"2012-10-17\",
        \"Statement\": [
            {
                \"Effect\": \"Allow\",
                \"Action\": [
                    \"logs:CreateLogGroup\",
                    \"logs:CreateLogStream\",
                    \"logs:PutLogEvents\"
                ],
                \"Resource\": \"*\"
            },
            {
                \"Effect\": \"Allow\",
                \"Action\": [
                    \"s3:GetObject\",
                    \"s3:GetObjectVersion\",
                    \"s3:PutObject\",
                    \"s3:ListBucket\"
                ],
                \"Resource\": [
                    \"arn:aws:s3:::${BUCKET_NAME}\",
                    \"arn:aws:s3:::${BUCKET_NAME}/*\"
                ]
            }
        ]
    }" \
    --region "${REGION}"

echo "Rollback complete. CodeBuild S3 permissions restored."
echo "============================================"
