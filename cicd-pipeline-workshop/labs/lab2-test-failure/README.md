# Lab 2: Test Stage Failure - Regression Bugs

## Scenario

A code change introduces two subtle bugs in the application:
1. The `/api/status` endpoint returns `'degraded'` instead of `'operational'`
2. The `/api/process` endpoint no longer includes the `'processed'` field in its response

The build stage passes (code compiles fine), but the test stage catches these regressions through unit tests.

## What Gets Broken

Application code is modified with behavioral changes that break the API contract. Existing tests catch the regressions.

## Impact Chain

1. Source stage picks up the new code
2. Build stage succeeds (code is syntactically valid)
3. Test stage FAILS -- 2 of 4 tests fail with assertion errors
4. Deploy stage never executes (pipeline stops)
5. CloudWatch alarms fire: `test-failures`, `pipeline-failures`

## Instructions

### Step 1: Inject the failure

```bash
./inject.sh devops-agent-cicd
```

### Step 2: Monitor pipeline progression

Watch the pipeline progress through Source -> Build -> Test:
```bash
watch -n 10 "aws codepipeline get-pipeline-state \
    --name devops-agent-cicd-pipeline \
    --query 'stageStates[*].{Stage:stageName,Status:latestExecution.status}' \
    --output table"
```

### Step 3: Review test results in CodeBuild

```bash
BUILD_ID=$(aws codebuild list-builds-for-project \
    --project-name devops-agent-cicd-test \
    --query 'ids[0]' --output text)

aws logs get-log-events \
    --log-group-name "/aws/codebuild/devops-agent-cicd-test" \
    --log-stream-name "$(aws codebuild batch-get-builds --ids ${BUILD_ID} --query 'builds[0].logs.streamName' --output text)" \
    --query 'events[*].message' --output text | tail -20
```

### Step 4: Trigger DevOps Agent investigation

Ask DevOps Agent: *"The pipeline is failing at the test stage. Can you analyze the test failures?"*

### Step 5: Review findings

Expected findings:
- **Root cause**: Two test failures -- `test_status_is_operational` (AssertionError: 'degraded' != 'operational') and `test_process_returns_processed_flag` (KeyError: 'processed')
- **Evidence**: CodeBuild test logs showing exact assertion errors
- **Correlation**: Code change that modified endpoint behavior
- **Recommendation**: Fix the `/api/status` endpoint to return 'operational' and restore the 'processed' field in `/api/process`

### Step 6: Rollback

```bash
./rollback.sh devops-agent-cicd
```

## Key DevOps Agent Capabilities Demonstrated

- CodeBuild test log analysis
- Pipeline multi-stage failure correlation
- Test failure pattern recognition (assertion errors vs. crashes)
- Code change impact analysis
