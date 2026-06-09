# Module Project Solution — Full CI/CD Pipeline

A complete CI/CD pipeline for a Dockerised web app using GitHub Actions (primary) and CircleCI (equivalent).

---

## Pipeline Overview

```
Push to main / PR
       │
       ▼
┌──────────────┐
│ Lint & Test  │  ← runs on all pushes and PRs
└──────┬───────┘
       │ (main branch only)
       ▼
┌──────────────┐
│  Build &     │  ← builds Docker image, scans for vulns, pushes to ECR
│  Push to ECR │     tagged with Git SHA + latest
└──────┬───────┘
       │
       ▼
┌──────────────┐
│   Deploy     │  ← automatic, updates ECS staging service
│   Staging    │     notifies Slack on success/failure
└──────┬───────┘
       │
       ▼
┌──────────────┐
│   Manual     │  ← GitHub Environment protection rules require approval
│   Approval   │
└──────┬───────┘
       │
       ▼
┌──────────────┐
│   Deploy     │  ← same flow as staging, notifies Slack
│   Production │
└──────────────┘
```

---

## Files

| File | Purpose |
|------|---------|
| `.github/workflows/ci-cd.yml` | Full GitHub Actions pipeline |
| `.circleci-config.yml` | Equivalent CircleCI pipeline (rename to `.circleci/config.yml` to use) |

---

## Required Secrets

### GitHub Secrets

| Secret | Description |
|--------|-------------|
| `AWS_ROLE_ARN` | IAM role for ECR push (OIDC) |
| `AWS_DEPLOY_ROLE_ARN` | IAM role for ECS deploy (OIDC) |
| `SLACK_WEBHOOK` | Slack incoming webhook URL |

### GitHub Environments

Set up two environments in repo settings:
- `staging` — no required reviewers, automatic
- `prod` — required reviewers (your team), restricts to `main` branch

### CircleCI Environment Variables

Set in Project Settings → Environment Variables:
- `AWS_ACCOUNT_ID`
- `AWS_REGION`
- `AWS_ROLE_ARN`
- `ECR_REPO`
- `SLACK_WEBHOOK`

---

## AWS Setup

```bash
# OIDC provider (one time per account)
aws iam create-open-id-connect-provider \
  --url https://token.actions.githubusercontent.com \
  --client-id-list sts.amazonaws.com \
  --thumbprint-list 6938fd4d98bab03faadb97b34396831e3780aea1

# ECR repo
aws ecr create-repository --repository-name myapp --region ap-south-1

# IAM role for ECR push
aws iam create-role --role-name github-actions-ecr \
  --assume-role-policy-document file://trust-policy.json
aws iam attach-role-policy --role-name github-actions-ecr \
  --policy-arn arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryPowerUser

# IAM role for ECS deploy (separate role, separate permissions)
aws iam create-role --role-name github-actions-ecs-deploy \
  --assume-role-policy-document file://trust-policy.json
# Attach custom policy with only ecs:UpdateService, ecs:RegisterTaskDefinition, etc.
```

---

## Key Design Decisions

**Separate roles for build and deploy.** The ECR push role cannot touch ECS. The ECS deploy role cannot push to ECR. Least privilege throughout.

**OIDC for all AWS auth.** No stored access keys anywhere. Credentials expire when the workflow run ends.

**Image tagged by Git SHA.** Every deployment is fully traceable to a commit. `latest` is pushed for convenience but never used in deploy commands.

**Vulnerability scanning before push.** Trivy scans the base image before build and the final image after push. Critical vulnerabilities fail the pipeline.

**Manual approval via GitHub Environments.** The `prod` environment requires approval from a designated reviewer. Even if a pipeline is triggered on main, prod never deploys without a human sign-off.

**Concurrency control.** `cancel-in-progress: true` prevents queued pipeline runs from piling up when multiple commits are pushed quickly.
