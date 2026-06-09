# GitHub Actions — Secrets & OIDC

Managing credentials in CI/CD is where most security mistakes happen. This note covers doing it right: GitHub Secrets for short-lived values, and OIDC for AWS so you never store long-term access keys at all.

---

## GitHub Secrets

Secrets are encrypted key-value pairs stored in GitHub. They are never printed in logs (GitHub masks them automatically).

**Where to store them:**
- **Repository secrets** — available to all workflows in the repo
- **Environment secrets** — scoped to a specific environment (staging, prod). Only workflows targeting that environment can access them.
- **Organisation secrets** — shared across multiple repos (useful for shared ECR tokens, Slack webhooks, etc.)

```yaml
# Access in workflow
steps:
  - run: echo "Connecting to ${{ secrets.DATABASE_URL }}"
  - run: ./deploy.sh
    env:
      DEPLOY_TOKEN: ${{ secrets.DEPLOY_TOKEN }}
      SLACK_WEBHOOK: ${{ secrets.SLACK_WEBHOOK }}
```

**Set secrets via CLI:**
```bash
# Repository secret
gh secret set DATABASE_URL --body "postgres://..."

# Environment secret
gh secret set DATABASE_URL --env staging --body "postgres://staging..."
gh secret set DATABASE_URL --env prod    --body "postgres://prod..."

# List secrets (names only — values never shown)
gh secret list
gh secret list --env prod
```

---

## GitHub Environments

Environments let you gate deployments with required reviewers and environment-specific secrets.

```yaml
jobs:
  deploy-prod:
    runs-on: ubuntu-latest
    environment: prod          # links to the 'prod' environment in GitHub

    steps:
      - name: Deploy
        env:
          API_KEY: ${{ secrets.API_KEY }}   # uses prod environment's API_KEY
        run: ./deploy.sh prod
```

In GitHub repo settings → Environments → prod:
- **Required reviewers** — adds a manual approval gate before the job runs
- **Wait timer** — optional delay before deployment starts
- **Environment secrets** — only accessible to workflows using this environment
- **Deployment branches** — restrict which branches can deploy to this environment

This is the right way to implement "staging deploys automatically, prod requires approval."

---

## OIDC — No More Stored AWS Credentials

The old way was storing `AWS_ACCESS_KEY_ID` and `AWS_SECRET_ACCESS_KEY` as GitHub Secrets. Problems:
- Long-term credentials that rotate manually (or don't get rotated)
- Anyone with repo access can potentially extract them
- Keys get leaked in git history, logs, or error messages

**OIDC (OpenID Connect)** is the right way. GitHub proves its identity to AWS and gets temporary credentials per workflow run. No stored secrets.

### Set Up OIDC — One Time Per AWS Account

```bash
# 1. Create the OIDC identity provider in AWS
aws iam create-open-id-connect-provider \
  --url https://token.actions.githubusercontent.com \
  --client-id-list sts.amazonaws.com \
  --thumbprint-list 6938fd4d98bab03faadb97b34396831e3780aea1
```

```bash
# 2. Create an IAM role that GitHub can assume
# Trust policy — who can assume this role
TRUST_POLICY='{
  "Version": "2012-10-17",
  "Statement": [{
    "Effect": "Allow",
    "Principal": {
      "Federated": "arn:aws:iam::ACCOUNT_ID:oidc-provider/token.actions.githubusercontent.com"
    },
    "Action": "sts:AssumeRoleWithWebIdentity",
    "Condition": {
      "StringLike": {
        "token.actions.githubusercontent.com:sub": "repo:YOUR_ORG/YOUR_REPO:*"
      },
      "StringEquals": {
        "token.actions.githubusercontent.com:aud": "sts.amazonaws.com"
      }
    }
  }]
}'

aws iam create-role \
  --role-name github-actions-deploy \
  --assume-role-policy-document "$TRUST_POLICY"

# 3. Attach only the permissions the pipeline needs
aws iam attach-role-policy \
  --role-name github-actions-deploy \
  --policy-arn arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryPowerUser

# For EKS deploys, add:
# aws iam attach-role-policy --role-name github-actions-deploy \
#   --policy-arn arn:aws:iam::aws:policy/AmazonEKSClusterPolicy
```

### Use OIDC in Your Workflow

```yaml
permissions:
  id-token: write    # REQUIRED — allows GitHub to request an OIDC token
  contents: read

jobs:
  deploy:
    runs-on: ubuntu-latest

    steps:
      - uses: actions/checkout@v4

      - name: Configure AWS credentials via OIDC
        uses: aws-actions/configure-aws-credentials@v4
        with:
          role-to-assume: arn:aws:iam::123456789012:role/github-actions-deploy
          aws-region: ap-south-1
          # Optional: session name for CloudTrail audit trail
          role-session-name: github-${{ github.run_id }}

      # From here, all AWS CLI and SDK calls use the assumed role
      - name: Push to ECR
        run: |
          aws ecr get-login-password | docker login --username AWS --password-stdin $ECR_REGISTRY
          docker push $ECR_REGISTRY/myapp:${{ github.sha }}
```

### Lock Down the Trust Policy

The condition `"repo:YOUR_ORG/YOUR_REPO:*"` allows any workflow in that repo. You can be more specific:

```json
// Only allow from main branch
"token.actions.githubusercontent.com:sub": "repo:myorg/myrepo:ref:refs/heads/main"

// Only allow from a specific environment
"token.actions.githubusercontent.com:sub": "repo:myorg/myrepo:environment:prod"

// Only allow tags
"token.actions.githubusercontent.com:sub": "repo:myorg/myrepo:ref:refs/tags/*"
```

Locking to `environment:prod` means only workflows that reference the `prod` GitHub Environment can assume the prod deployment role. This is the correct way to prevent staging workflows from touching prod infrastructure.

---

## Secrets That Cannot Be Stored in GitHub

Some things should never go into GitHub Secrets even encrypted — database passwords, private keys for production systems. For these, use AWS Secrets Manager or SSM Parameter Store and fetch them at runtime:

```yaml
- name: Fetch secrets from AWS Secrets Manager
  run: |
    DB_PASSWORD=$(aws secretsmanager get-secret-value \
      --secret-id prod/myapp/db-password \
      --query SecretString --output text)
    # Add to GITHUB_ENV so later steps can use it
    echo "DB_PASSWORD=${DB_PASSWORD}" >> $GITHUB_ENV
    # Or pass directly to a command
    ./deploy.sh --db-password "${DB_PASSWORD}"
```

This way the secret value never exists in GitHub — it lives in AWS and is fetched ephemerally per run.

---

## Key Insight for DevOps

Set up OIDC on day one. The 15 minutes it takes to configure the IAM role and OIDC provider is far cheaper than the incident response when an access key leaks. With OIDC, there is no long-term credential to leak — the credentials expire when the workflow run ends, typically within an hour.

Restrict the OIDC trust policy to specific environments or branches. A staging workflow should never be able to assume a production role, even if someone manually triggers it against the wrong environment.
