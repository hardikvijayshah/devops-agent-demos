# Lab 5: Pipeline Permission Issue (IAM)

## Scenario

The CodeBuild service role has been modified to explicitly deny S3 access. When the pipeline triggers, CodeBuild cannot download source artifacts from S3 or upload build artifacts, causing the build stage to fail with `AccessDenied` errors.

This simulates a real-world scenario where an IAM policy change (perhaps from a security audit remediation, SCPs, or permission boundary update) inadvertently breaks CI/CD pipeline permissions.

## What Gets Broken

The CodeBuild IAM role's inline policy is replaced with one that:
- Keeps CloudWatch Logs permissions (so CodeBuild can still log)
- Adds an explicit `Deny` on `s3:GetObject` and `s3:PutObject`

## Impact Chain

1. Pipeline Source stage succeeds (uses CodePipeline's role, not CodeBuild's)
2. Build stage starts, but CodeBuild cannot access S3
3. CodeBuild fails with `AccessDenied` when trying to download source
4. Pipeline fails at Build stage
5. CloudWatch alarms fire: `build-failures`, `pipeline-failures`
6. CloudTrail shows the IAM policy change

## Why This Lab Is Interesting

IAM permission issues are among the **hardest to diagnose** in CI/CD pipelines because:
- The error messages are often generic (`AccessDenied`)
- The root cause (IAM policy change) is in a different service than where the error appears
- CloudTrail correlation is needed to connect the IAM change to the CodeBuild failure

## Instructions

### Step 1: Inject the failure

```bash
./inject.sh devops-agent-cicd
```

### Step 2: Monitor the build failure

```bash
aws codepipeline get-pipeline-state \
    --name devops-agent-cicd-pipeline \
    --query 'stageStates[?stageName==`Build`].latestExecution' \
    --output table
```

### Step 3: Check CodeBuild logs for access denied

```bash
BUILD_ID=$(aws codebuild list-builds-for-project \
    --project-name devops-agent-cicd-build \
    --query 'ids[0]' --output text)

aws codebuild batch-get-builds \
    --ids "${BUILD_ID}" \
    --query 'builds[0].{Status:buildStatus,Phase:currentPhase,StatusReason:phases[-1].contexts[0].message}' \
    --output table
```

### Step 4: Trigger DevOps Agent investigation

Ask DevOps Agent: *"The build pipeline is failing with access denied errors. Can you check what changed?"*

### Step 5: Review findings

Expected findings:
- **Root cause**: IAM policy change on CodeBuild role -- explicit Deny on S3 actions
- **Evidence**: CodeBuild logs showing `AccessDenied`, CloudTrail showing `PutRolePolicy` event
- **Correlation**: IAM change timestamp matches build failure onset
- **Recommendation**: Remove the explicit Deny statement and restore S3 access for the CodeBuild role

### Step 6: Rollback

```bash
./rollback.sh devops-agent-cicd
```

## Key DevOps Agent Capabilities Demonstrated

- IAM policy change detection via CloudTrail
- Cross-service correlation (IAM -> CodeBuild -> CodePipeline)
- Access denied error diagnosis
- Security-related change impact analysis
