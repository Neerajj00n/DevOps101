# GitHub Actions — Docker & ECR

Building and pushing Docker images is one of the most common CI/CD tasks. This covers the full workflow: build → tag → push to ECR, done correctly.

---

## The Full Docker + ECR Workflow

```yaml
# .github/workflows/build-push.yml
name: Build and Push

on:
  push:
    branches: [main]

env:
  AWS_REGION: ap-south-1
  ECR_REGISTRY: 123456789012.dkr.ecr.ap-south-1.amazonaws.com
  ECR_REPOSITORY: myapp

permissions:
  id-token: write    # for OIDC auth to AWS
  contents: read

jobs:
  build-and-push:
    runs-on: ubuntu-latest

    outputs:
      image-tag: ${{ steps.meta.outputs.image-tag }}

    steps:
      - name: Checkout
        uses: actions/checkout@v4

      # Auth to AWS via OIDC (no stored access keys — see secrets-oidc notes)
      - name: Configure AWS credentials
        uses: aws-actions/configure-aws-credentials@v4
        with:
          role-to-assume: arn:aws:iam::123456789012:role/github-actions-deploy
          aws-region: ${{ env.AWS_REGION }}

      # Log in to ECR
      - name: Login to Amazon ECR
        id: ecr-login
        uses: aws-actions/amazon-ecr-login@v2

      # Set image tags
      - name: Set image metadata
        id: meta
        run: |
          SHORT_SHA=$(git rev-parse --short HEAD)
          echo "image-tag=${SHORT_SHA}" >> $GITHUB_OUTPUT
          echo "full-image=${{ env.ECR_REGISTRY }}/${{ env.ECR_REPOSITORY }}:${SHORT_SHA}" >> $GITHUB_OUTPUT

      # Build with layer caching
      - name: Set up Docker Buildx
        uses: docker/setup-buildx-action@v3

      - name: Build and push
        uses: docker/build-push-action@v5
        with:
          context: .
          push: true
          tags: |
            ${{ env.ECR_REGISTRY }}/${{ env.ECR_REPOSITORY }}:${{ steps.meta.outputs.image-tag }}
            ${{ env.ECR_REGISTRY }}/${{ env.ECR_REPOSITORY }}:latest
          cache-from: type=gha          # GitHub Actions cache for layers
          cache-to: type=gha,mode=max
          build-args: |
            BUILD_DATE=${{ github.run_id }}
            GIT_SHA=${{ github.sha }}

      - name: Print image URI
        run: echo "Image pushed → ${{ steps.meta.outputs.full-image }}"
```

---

## Multi-stage Builds in CI

Multi-stage Dockerfiles keep production images small. The CI pipeline should target the production stage, not accidentally build the dev stage.

```dockerfile
# Dockerfile
FROM node:20-alpine AS deps
WORKDIR /app
COPY package*.json ./
RUN npm ci --only=production

FROM node:20-alpine AS builder
WORKDIR /app
COPY --from=deps /app/node_modules ./node_modules
COPY . .
RUN npm run build

FROM node:20-alpine AS runner
WORKDIR /app
ENV NODE_ENV=production
COPY --from=builder /app/dist ./dist
COPY --from=deps /app/node_modules ./node_modules
USER node
EXPOSE 3000
CMD ["node", "dist/index.js"]
```

```yaml
# In your workflow — build only the final stage
- name: Build and push
  uses: docker/build-push-action@v5
  with:
    context: .
    target: runner      # explicit target stage
    push: true
    tags: ...
```

---

## Building for Multiple Platforms

If you deploy to ARM (Graviton EC2, Apple Silicon, etc.):

```yaml
- name: Set up QEMU (for cross-platform builds)
  uses: docker/setup-qemu-action@v3

- name: Set up Docker Buildx
  uses: docker/setup-buildx-action@v3

- name: Build and push multi-platform
  uses: docker/build-push-action@v5
  with:
    platforms: linux/amd64,linux/arm64
    push: true
    tags: ${{ env.ECR_REGISTRY }}/${{ env.ECR_REPOSITORY }}:${{ steps.meta.outputs.image-tag }}
```

---

## Run Tests Inside Docker

Run your tests in the same container that will go to production. Eliminates "works in CI but breaks in prod" environment differences.

```yaml
- name: Run tests in Docker
  run: |
    docker build --target builder -t myapp-test .
    docker run --rm \
      -e DATABASE_URL=${{ secrets.TEST_DATABASE_URL }} \
      myapp-test \
      npm test
```

Or use Docker Compose for integration tests:

```yaml
- name: Start services
  run: docker compose -f docker-compose.test.yml up -d

- name: Wait for services
  run: |
    timeout 60 bash -c 'until docker compose -f docker-compose.test.yml exec -T db pg_isready; do sleep 2; done'

- name: Run integration tests
  run: docker compose -f docker-compose.test.yml run test

- name: Tear down
  if: always()
  run: docker compose -f docker-compose.test.yml down -v
```

---

## Scan Images for Vulnerabilities

```yaml
- name: Build image (local, not pushed yet)
  uses: docker/build-push-action@v5
  with:
    context: .
    load: true          # load into local Docker daemon, do not push
    tags: myapp:scan

- name: Scan with Trivy
  uses: aquasecurity/trivy-action@master
  with:
    image-ref: myapp:scan
    format: table
    exit-code: 1              # fail the pipeline if HIGH/CRITICAL found
    severity: HIGH,CRITICAL

# Only push if scan passes (scan step must succeed)
- name: Push to ECR
  uses: docker/build-push-action@v5
  with:
    context: .
    push: true
    tags: ...
```

---

## ECR Lifecycle Policy (keep registry clean)

Your pipeline should also manage ECR cleanup — otherwise the registry fills up and costs money:

```bash
# Set lifecycle policy to keep only last 30 images
aws ecr put-lifecycle-policy \
  --repository-name myapp \
  --lifecycle-policy-text '{
    "rules": [{
      "rulePriority": 1,
      "description": "Keep last 30 images",
      "selection": {
        "tagStatus": "tagged",
        "tagPrefixList": ["sha-"],
        "countType": "imageCountMoreThan",
        "countNumber": 30
      },
      "action": { "type": "expire" }
    }, {
      "rulePriority": 2,
      "description": "Delete untagged images after 1 day",
      "selection": {
        "tagStatus": "untagged",
        "countType": "sinceImagePushed",
        "countUnit": "days",
        "countNumber": 1
      },
      "action": { "type": "expire" }
    }]
  }'
```

---

## Key Insight for DevOps

Always tag images with the Git SHA, not just `latest`. When an incident happens at 2am and you need to know exactly what code is running in production, `myapp:a3f8c12` is immediately traceable. `latest` tells you nothing.

The `cache-from: type=gha` / `cache-to: type=gha,mode=max` options in `docker/build-push-action` use GitHub's built-in cache for Docker layers. For a typical Node or Python app this cuts build time by 60–80% after the first run.
