# GitHub Actions — Reusable Workflows & Composite Actions

When you have the same build or deploy logic repeated across multiple repos or workflows, you have a maintenance problem. Reusable workflows and composite actions solve this.

---

## Two Ways to Reuse Logic

| | Reusable Workflow | Composite Action |
|---|---|---|
| **Scope** | Entire workflow (multiple jobs) | Single step or group of steps |
| **Called from** | Another workflow's `jobs` section | A step within any job |
| **Secrets** | Must be explicitly passed | Inherited from caller |
| **Runners** | Each job picks its own runner | Uses caller's runner |
| **Best for** | Standard build+push pipelines | Shared setup steps (auth, setup tools) |

---

## Reusable Workflows

A reusable workflow is a regular workflow file that uses `workflow_call` as its trigger.

```yaml
# .github/workflows/build-and-push.yml  (in a shared repo or same repo)
name: Build and Push Docker Image

on:
  workflow_call:
    inputs:
      ecr-repository:
        required: true
        type: string
      aws-region:
        required: false
        type: string
        default: ap-south-1
      dockerfile:
        required: false
        type: string
        default: Dockerfile
    secrets:
      aws-role-arn:
        required: true
    outputs:
      image-tag:
        description: "The pushed image tag (short SHA)"
        value: ${{ jobs.build.outputs.image-tag }}

permissions:
  id-token: write
  contents: read

jobs:
  build:
    runs-on: ubuntu-latest

    outputs:
      image-tag: ${{ steps.meta.outputs.tag }}

    steps:
      - uses: actions/checkout@v4

      - name: Configure AWS credentials
        uses: aws-actions/configure-aws-credentials@v4
        with:
          role-to-assume: ${{ secrets.aws-role-arn }}
          aws-region: ${{ inputs.aws-region }}

      - name: Login to ECR
        uses: aws-actions/amazon-ecr-login@v2

      - name: Set image tag
        id: meta
        run: echo "tag=$(git rev-parse --short HEAD)" >> $GITHUB_OUTPUT

      - name: Set up Buildx
        uses: docker/setup-buildx-action@v3

      - name: Build and push
        uses: docker/build-push-action@v5
        with:
          context: .
          file: ${{ inputs.dockerfile }}
          push: true
          tags: |
            ${{ steps.ecr-login.outputs.registry }}/${{ inputs.ecr-repository }}:${{ steps.meta.outputs.tag }}
            ${{ steps.ecr-login.outputs.registry }}/${{ inputs.ecr-repository }}:latest
          cache-from: type=gha
          cache-to: type=gha,mode=max
```

**Calling the reusable workflow:**

```yaml
# .github/workflows/ci.yml  (in your application repo)
name: CI

on:
  push:
    branches: [main]

jobs:
  build:
    uses: myorg/shared-workflows/.github/workflows/build-and-push.yml@main
    with:
      ecr-repository: myapp
      aws-region: ap-south-1
    secrets:
      aws-role-arn: ${{ secrets.AWS_DEPLOY_ROLE_ARN }}

  deploy:
    needs: build
    runs-on: ubuntu-latest
    steps:
      - run: echo "Deploying image tag ${{ needs.build.outputs.image-tag }}"
```

---

## Composite Actions

A composite action wraps multiple steps into a single reusable `uses:` step. Lives in its own directory with an `action.yml`.

```yaml
# .github/actions/setup-aws/action.yml
name: Setup AWS
description: Configure AWS credentials and ECR login via OIDC

inputs:
  role-arn:
    description: IAM role ARN to assume
    required: true
  aws-region:
    description: AWS region
    required: false
    default: ap-south-1

outputs:
  registry:
    description: ECR registry URL
    value: ${{ steps.ecr.outputs.registry }}

runs:
  using: composite
  steps:
    - name: Configure AWS credentials
      uses: aws-actions/configure-aws-credentials@v4
      with:
        role-to-assume: ${{ inputs.role-arn }}
        aws-region: ${{ inputs.aws-region }}

    - name: Login to ECR
      id: ecr
      uses: aws-actions/amazon-ecr-login@v2
```

**Using the composite action:**

```yaml
jobs:
  deploy:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4

      - name: Setup AWS
        id: aws
        uses: ./.github/actions/setup-aws    # local action
        # uses: myorg/shared-actions/.github/actions/setup-aws@v1  # from another repo
        with:
          role-arn: ${{ secrets.AWS_ROLE_ARN }}

      - name: Push to ECR
        run: docker push ${{ steps.aws.outputs.registry }}/myapp:latest
```

---

## Practical Reuse Patterns

**Pattern 1: Centralised pipeline repo**
```
myorg/
├── shared-workflows/         ← shared reusable workflows
│   └── .github/workflows/
│       ├── build-push.yml
│       ├── deploy-eks.yml
│       └── terraform-plan.yml
├── app-one/
│   └── .github/workflows/ci.yml   ← calls shared-workflows
└── app-two/
    └── .github/workflows/ci.yml   ← calls shared-workflows
```

Every app uses the same build/push/deploy logic. Update once, all apps benefit.

**Pattern 2: Same-repo reuse with `workflow_call`**
```
.github/
├── workflows/
│   ├── _build.yml          ← reusable (prefixed with _ by convention)
│   ├── _deploy.yml         ← reusable
│   ├── ci.yml              ← calls _build and _deploy for staging
│   └── release.yml         ← calls _build and _deploy for prod
└── actions/
    └── setup-tools/
        └── action.yml      ← composite action
```

---

## Versioning Reusable Workflows

```yaml
# Pin to a specific tag (recommended for production)
uses: myorg/shared-workflows/.github/workflows/build-push.yml@v2.1.0

# Pin to a branch (useful during development)
uses: myorg/shared-workflows/.github/workflows/build-push.yml@main

# Pin to a SHA (most stable — immune to tag mutations)
uses: myorg/shared-workflows/.github/workflows/build-push.yml@a3f8c12d...
```

---

## Key Insight for DevOps

The biggest benefit of reusable workflows is not avoiding copy-paste — it is **enforcing standards**. When every team's deploy workflow calls the same `deploy-eks.yml`, you know every deploy goes through the same security checks, uses the same OIDC auth, and follows the same approval process. One team cannot skip the vulnerability scan by accident.

Keep reusable workflows simple and well-documented. A workflow that is too clever to understand is not reused — people copy-paste instead and you are back where you started.
