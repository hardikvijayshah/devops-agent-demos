#!/usr/bin/env pwsh
# Push each workshop to its individual GitHub repo
# Run this after Code Defender approves all 4 repos

$ErrorActionPreference = "Continue"
$env:GIT_AUTHOR_NAME = "Shah"
$env:GIT_AUTHOR_EMAIL = "hardvsha@amazon.com"
$env:GIT_COMMITTER_NAME = "Shah"
$env:GIT_COMMITTER_EMAIL = "hardvsha@amazon.com"

$baseDir = Get-Location
$sharedFiles = @("LICENSE", "CODE_OF_CONDUCT.md", "CONTRIBUTING.md")

$workshops = @(
    @{ Folder = "cicd-pipeline-workshop"; Repo = "https://github.com/hardikvijayshah/devops-agent-cicd-pipeline-workshop.git"; Message = "Initial commit: CI/CD Pipeline Failure Investigation Workshop" },
    @{ Folder = "serverless-workshop"; Repo = "https://github.com/hardikvijayshah/devops-agent-serverless-workshop.git"; Message = "Initial commit: Serverless Application Troubleshooting Workshop" },
    @{ Folder = "proactive-evaluations-workshop"; Repo = "https://github.com/hardikvijayshah/devops-agent-proactive-evaluations-workshop.git"; Message = "Initial commit: Proactive Evaluations Workshop" },
    @{ Folder = "jenkins-ecs-deployment-workshop"; Repo = "https://github.com/hardikvijayshah/devops-agent-jenkins-ecs-workshop.git"; Message = "Initial commit: Jenkins CI/CD + ECS Deployment Failure Workshop" }
)

foreach ($w in $workshops) {
    Write-Host "`n============================================" -ForegroundColor Cyan
    Write-Host "Pushing: $($w.Folder)" -ForegroundColor Cyan
    Write-Host "To: $($w.Repo)" -ForegroundColor Cyan
    Write-Host "============================================" -ForegroundColor Cyan

    $tempDir = Join-Path $env:TEMP "repo-push-$($w.Folder)"
    if (Test-Path $tempDir) { Remove-Item -Recurse -Force $tempDir }
    New-Item -ItemType Directory -Path $tempDir -Force | Out-Null

    # Copy workshop files
    Copy-Item -Recurse -Force (Join-Path $baseDir $w.Folder "\*") $tempDir

    # Copy shared files
    foreach ($f in $sharedFiles) {
        $src = Join-Path $baseDir $f
        if (Test-Path $src) { Copy-Item -Force $src $tempDir }
    }

    # Init, commit, push
    Set-Location $tempDir
    git init 2>&1 | Out-Null
    git add -A 2>&1 | Out-Null
    git commit -m $w.Message 2>&1 | Out-Null
    git remote add origin $w.Repo
    git push -u origin master 2>&1
    
    if ($LASTEXITCODE -eq 0) {
        Write-Host "  SUCCESS" -ForegroundColor Green
    } else {
        Write-Host "  FAILED (Code Defender may not have approved yet)" -ForegroundColor Red
    }

    Set-Location $baseDir
    Remove-Item -Recurse -Force $tempDir
}

Write-Host "`n============================================" -ForegroundColor Green
Write-Host "All done!" -ForegroundColor Green
Write-Host "============================================" -ForegroundColor Green
