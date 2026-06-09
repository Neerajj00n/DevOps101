# Lab 03: Multi-Environment Deployment Pipeline

In this lab, you'll build a GitHub Actions workflow that deploys to multiple environments based on different Git events.

## Objectives

- Create a workflow that deploys to a staging environment when PRs are merged to the main branch
- Set up deployment to production when a release tag is pushed
- Implement environment-specific configuration
- Add manual approval gates before production deployment

## Prerequisites

- Completed Lab 02 (Docker pipeline)
- A GitHub repository with a Dockerized application
- AWS account with ECR repository and deployment environments

## Lab Steps

### 1. Create Environment-Specific Configuration

Create two configuration files for your different environments:

```
config/
├── staging.env
└── production.env
```

### 2. Create a Multi-Environment Workflow

Create `.github/workflows/deploy.yml` with the following content:

```yaml
name: Deploy

on:
  push:
    branches:
      - main
    tags:
      - 'v*'

jobs:
  build-and-push:
    runs-on: ubuntu-latest
    steps:
      - name: Checkout code
        uses: actions/checkout@v3
      
      - name: Set up Docker Buildx
        uses: docker/setup-buildx-action@v2
      
      - name: Configure AWS credentials
        uses: aws-actions/configure-aws-credentials@v1
        with:
          role-to-assume: ${{ secrets.AWS_ROLE_ARN }}
          aws-region: us-east-1
      
      - name: Login to Amazon ECR
        id: login-ecr
        uses: aws-actions/amazon-ecr-login@v1
      
      - name: Build and push Docker image
        uses: docker/build-push-action@v4
        with:
          context: .
          push: true
          tags: |
            ${{ steps.login-ecr.outputs.registry }}/my-app:${{ github.sha }}
            ${{ steps.login-ecr.outputs.registry }}/my-app:latest

  deploy-staging:
    needs: build-and-push
    if: github.ref == 'refs/heads/main'
    runs-on: ubuntu-latest
    environment: staging
    steps:
      - name: Deploy to staging
        run: |
          echo "Deploying to staging environment..."
          # Add your deployment commands here

  deploy-production:
    needs: build-and-push
    if: startsWith(github.ref, 'refs/tags/v')
    runs-on: ubuntu-latest
    environment:
      name: production
      url: https://my-production-app.example.com
    steps:
      - name: Deploy to production
        run: |
          echo "Deploying to production environment..."
          # Add your deployment commands here
```

### 3. Configure Environment Protection Rules

1. In your GitHub repository, go to Settings > Environments
2. Create environments for "staging" and "production"
3. For production, add protection rules:
   - Required reviewers (add team members who can approve deployments)
   - Wait timer (e.g., 10 minutes)

### 4. Test the Workflow

1. Make a change to your code and create a PR
2. Once the PR is approved and merged to main, observe the staging deployment
3. Create a release tag (e.g., `v1.0.0`) and push it to trigger the production deployment flow
4. Observe the approval process before production deployment

## Extension Tasks

- Add environment-specific variables in GitHub Environments settings
- Implement a rollback mechanism for failed deployments
- Add post-deployment smoke tests to verify the deployment was successful

## Submission

Submit screenshots showing:
1. Successful staging deployment after a PR merge
2. Production deployment approval interface
3. Successful production deployment after tag release