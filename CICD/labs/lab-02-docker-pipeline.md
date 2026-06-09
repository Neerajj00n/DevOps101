# Lab 02 — Docker Pipeline with ECR & OIDC

**Goal:** Build a Docker image in CI and push it to ECR using OIDC authentication (no stored access keys).

**Time:** ~45 minutes  
**Prerequisites:** Lab 01 complete. AWS account with ECR access. A repo with a Dockerfile.

---

## Part 1 — Set Up OIDC in AWS (one time)

Run these in your terminal:

```bash
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
REPO="YOUR_GITHUB_ORG/YOUR_REPO"

# Create OIDC provider
aws iam create-open-id-connect-provider \
  --url https://token.actions.githubusercontent.com \
  --client-id-list sts.amazonaws.com \
  --thumbprint-list 6938fd4d98bab03faadb97b34396831e3780aea1

# Create IAM role for GitHub Actions
TRUST_POLICY=$(cat << EOF
{
  "Version": "2012-10-17",
  "Statement": [{
    "Effect": "Allow",
    "Principal": {
      "Federated": "arn:aws:iam::${ACCOUNT_ID}:oidc-provider/token.actions.githubusercontent.com"
    },
    "Action": "sts:AssumeRoleWithWebIdentity",
    "Condition": {
      "StringLike": {
        "token.actions.githubusercontent.com:sub": "repo:${REPO}:*"
      },
      "StringEquals": {
        "token.actions.githubusercontent.com:aud": "sts.amazonaws.com"
      }
    }
  }]
}
EOF
)

aws iam create-role \
  --role-name github-actions-ecr \
  --assume-role-policy-document "$TRUST_POLICY"

# Attach ECR push permissions
aws iam attach-role-policy \
  --role-name github-actions-ecr \
  --policy-arn arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryPowerUser

# Print the role ARN — you will need this
aws iam get-role --role-name github-actions-ecr \
  --query 'Role.Arn' --output text
```

---

## Part 2 — Create ECR Repository

```bash
aws ecr create-repository \
  --repository-name myapp \
  --region ap-south-1 \
  --image-scanning-configuration scanOnPush=true

# Set lifecycle policy to keep last 20 images
aws ecr put-lifecycle-policy \
  --repository-name myapp \
  --lifecycle-policy-text '{
    "rules": [{
      "rulePriority": 1,
      "selection": {
        "tagStatus": "tagged",
        "tagPrefixList": ["sha-"],
        "countType": "imageCountMoreThan",
        "countNumber": 20
      },
      "action": {"type": "expire"}
    }]
  }'
```

---

## Part 3 — Add Secrets to GitHub

```bash
# Add the role ARN as a GitHub secret (no static credentials!)
gh secret set AWS_ROLE_ARN --body "arn:aws:iam::ACCOUNT_ID:role/github-actions-ecr"
gh secret set ECR_REGISTRY --body "ACCOUNT_ID.dkr.ecr.ap-south-1.amazonaws.com"
```

---

## Part 4 — Write the Build & Push Workflow

Create `.github/workflows/build-push.yml`:

```yaml
name: Build and Push

on:
  push:
    branches: [main]
  pull_request:
    branches: [main]

env:
  AWS_REGION: ap-south-1
  ECR_REPOSITORY: myapp

permissions:
  id-token: write
  contents: read

jobs:
  build:
    name: Build Docker Image
    runs-on: ubuntu-latest

    outputs:
      image-tag: ${{ steps.meta.outputs.tag }}
      image-uri: ${{ steps.meta.outputs.uri }}

    steps:
      - name: Checkout
        uses: actions/checkout@v4

      - name: Configure AWS credentials (OIDC)
        uses: aws-actions/configure-aws-credentials@v4
        with:
          role-to-assume: ${{ secrets.AWS_ROLE_ARN }}
          aws-region: ${{ env.AWS_REGION }}

      - name: Login to ECR
        id: ecr-login
        uses: aws-actions/amazon-ecr-login@v2

      - name: Set image metadata
        id: meta
        run: |
          SHORT_SHA=$(git rev-parse --short HEAD)
          echo "tag=${SHORT_SHA}" >> $GITHUB_OUTPUT
          echo "uri=${{ steps.ecr-login.outputs.registry }}/${{ env.ECR_REPOSITORY }}:${SHORT_SHA}" >> $GITHUB_OUTPUT

      - name: Set up Docker Buildx
        uses: docker/setup-buildx-action@v3

      - name: Build and push
        uses: docker/build-push-action@v5
        with:
          context: .
          push: ${{ github.ref == 'refs/heads/main' }}   # only push on main
          tags: |
            ${{ steps.ecr-login.outputs.registry }}/${{ env.ECR_REPOSITORY }}:${{ steps.meta.outputs.tag }}
            ${{ steps.ecr-login.outputs.registry }}/${{ env.ECR_REPOSITORY }}:latest
          cache-from: type=gha
          cache-to: type=gha,mode=max

      - name: Summary
        if: github.ref == 'refs/heads/main'
        run: |
          echo "### Image pushed 🚀" >> $GITHUB_STEP_SUMMARY
          echo "**URI:** \`${{ steps.meta.outputs.uri }}\`" >> $GITHUB_STEP_SUMMARY
          echo "**Tag:** \`${{ steps.meta.outputs.tag }}\`" >> $GITHUB_STEP_SUMMARY
```

---

## Part 5 — Verify

```bash
# After the workflow runs on main, check ECR
aws ecr list-images \
  --repository-name myapp \
  --query 'imageIds[*].[imageTag]' \
  --output table

# Pull and run the image locally
aws ecr get-login-password --region ap-south-1 | \
  docker login --username AWS --password-stdin ACCOUNT_ID.dkr.ecr.ap-south-1.amazonaws.com

docker pull ACCOUNT_ID.dkr.ecr.ap-south-1.amazonaws.com/myapp:latest
docker run --rm ACCOUNT_ID.dkr.ecr.ap-south-1.amazonaws.com/myapp:latest
```

---

## Tasks to Complete

1. Push to `main` and confirm the image appears in ECR with a SHA tag.
2. Open a PR — confirm the image is built but NOT pushed (the `push: ${{ github.ref == 'refs/heads/main' }}` condition).
3. Check the GitHub Actions Summary tab — you should see the image URI printed there.
4. Pull the image locally and run it.
5. Push two more commits to `main` — confirm you now have 3 tagged images in ECR.

---

## What You Should Now Understand

- How OIDC eliminates stored AWS credentials from CI/CD
- How to condition steps on branch or event type
- How to pass values between steps and jobs using outputs
- How Docker layer caching works in GitHub Actions
- How to tag images with Git SHAs for traceability

---

## Next Lab

[Lab 03 — Multi-Environment Deployments →](./lab-03-multi-env.md)
