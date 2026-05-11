# Lab 1: Build Failure - Missing Dependency

## Scenario

A developer commits a change that adds `nonexistent-package-xyz==99.99.99` to `requirements.txt`. The CodeBuild build stage fails during `pip install` because the package doesn't exist in PyPI.

This simulates a real-world scenario where a dependency is misspelled, pinned to a non-existent version, or references a private package registry that CodeBuild can't access.

## What Gets Broken

`requirements.txt` is modified to include a non-existent pip package. The build stage fails during the install phase.

## Impact Chain

1. Pipeline Source stage succeeds (picks up new source from S3)
2. Pipeline Build stage fails at `pip install -r requirements.txt`
3. CodeBuild logs show `ERROR: Could not find a version that satisfies the requirement`
4. Pipeline stops -- Test and Deploy stages never execute
5. CloudWatch alarms fire: `build-failures`, `pipeline-failures`

## Instructions

### Step 1: Inject the failure

```bash
./inject.sh devops-agent-cicd
```

### Step 2: Monitor the pipeline

```bash
aws codepipeline get-pipeline-state \
    --name devops-agent-cicd-pipeline \
    --query 'stageStates[*].{Stage:stageName,Status:latestExecution.status}' \
    --output table
```

### Step 3: Check CodeBuild logs

```bash
BUILD_ID=$(aws codebuild list-builds-for-project \
    --project-name devops-agent-cicd-build \
    --query 'ids[0]' --output text)

aws codebuild batch-get-builds \
    --ids "${BUILD_ID}" \
    --query 'builds[0].{Status:buildStatus,Phase:currentPhase}' \
    --output table
```

### Step 4: Trigger DevOps Agent investigation

Ask DevOps Agent: *"Our CI/CD pipeline is failing at the build stage. What's wrong?"*

### Step 5: Review findings

Expected findings:
- **Root cause**: `pip install` failure for `nonexistent-package-xyz==99.99.99` -- package not found on PyPI
- **Evidence**: CodeBuild logs showing the exact pip error message
- **Correlation**: Source code change (requirements.txt modification) triggered the pipeline
- **Recommendation**: Remove or fix the invalid package reference in requirements.txt

### Step 6: Rollback

```bash
./rollback.sh devops-agent-cicd
```

## Key DevOps Agent Capabilities Demonstrated

- CodeBuild log analysis
- CodePipeline stage failure correlation
- Source change detection
- Build dependency troubleshooting
