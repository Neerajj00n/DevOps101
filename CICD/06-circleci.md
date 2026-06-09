# CircleCI

CircleCI is a dedicated CI/CD platform. It predates GitHub Actions and has some genuinely better features — particularly Docker Layer Caching (DLC), test splitting, and resource class control. Worth knowing, especially since many companies still use it heavily.

---

## Config File

CircleCI reads `.circleci/config.yml` from your repo root.

```yaml
version: 2.1   # always use 2.1 — it unlocks orbs and reusable config

# Orbs are reusable packages (like GitHub Actions marketplace)
orbs:
  aws-ecr: circleci/aws-ecr@9.0
  aws-cli: circleci/aws-cli@4.0
  node: circleci/node@5.0

# Reusable commands (like composite actions)
commands:
  install-deps:
    steps:
      - restore_cache:
          keys:
            - deps-{{ checksum "package-lock.json" }}
      - run: npm ci
      - save_cache:
          key: deps-{{ checksum "package-lock.json" }}
          paths:
            - node_modules

# Reusable job definitions
executors:
  node-executor:
    docker:
      - image: cimg/node:20.0
    resource_class: medium

jobs:
  test:
    executor: node-executor
    steps:
      - checkout
      - install-deps
      - run:
          name: Run tests
          command: npm test
      - store_test_results:
          path: ./test-results
      - store_artifacts:
          path: ./coverage

  build-and-push:
    machine:
      image: ubuntu-2204:current
      docker_layer_caching: true    # cache Docker layers between runs (CircleCI advantage)
    steps:
      - checkout
      - aws-cli/setup
      - run:
          name: Login to ECR
          command: |
            aws ecr get-login-password --region $AWS_REGION | \
              docker login --username AWS --password-stdin $ECR_REGISTRY
      - run:
          name: Build and push
          command: |
            IMAGE_TAG=$(git rev-parse --short HEAD)
            docker build -t $ECR_REGISTRY/$ECR_REPO:$IMAGE_TAG .
            docker push $ECR_REGISTRY/$ECR_REPO:$IMAGE_TAG
            docker tag $ECR_REGISTRY/$ECR_REPO:$IMAGE_TAG $ECR_REGISTRY/$ECR_REPO:latest
            docker push $ECR_REGISTRY/$ECR_REPO:latest

workflows:
  ci-cd:
    jobs:
      - test
      - build-and-push:
          requires:
            - test
          filters:
            branches:
              only: main
```

---

## Core Concepts vs GitHub Actions

| Concept | GitHub Actions | CircleCI |
|---------|----------------|----------|
| Config file | `.github/workflows/*.yml` | `.circleci/config.yml` |
| Reusable steps | Composite Actions | Commands |
| Reusable jobs | Reusable Workflows | Reusable job definitions |
| Reusable packages | Actions Marketplace | Orbs |
| Runner | `runs-on: ubuntu-latest` | `executor:` (docker/machine/macos) |
| Job dependencies | `needs:` | `requires:` in workflow |
| Parallel jobs | `strategy.matrix` | `parallelism:` + test splitting |
| Secrets | GitHub Secrets | Project/Context secrets |
| Manual approval | Environment protection rules | `type: approval` job |

---

## Executors — Where Jobs Run

```yaml
jobs:
  # Docker executor — fast startup, lightweight
  docker-job:
    docker:
      - image: cimg/python:3.12   # primary container
      - image: postgres:15        # service container (accessible as localhost)
        environment:
          POSTGRES_PASSWORD: test
    resource_class: medium       # small/medium/large/xlarge

  # Machine executor — full VM, needed for Docker builds
  machine-job:
    machine:
      image: ubuntu-2204:current
      docker_layer_caching: true
    resource_class: medium

  # macOS executor
  macos-job:
    macos:
      xcode: 15.0.0
```

**Resource classes:**

| Class | CPU | RAM | Use |
|-------|-----|-----|-----|
| small | 1 | 2GB | Lint, simple scripts |
| medium | 2 | 4GB | Tests, builds |
| large | 4 | 8GB | Heavy builds |
| xlarge | 8 | 16GB | Parallel test suites |

---

## Caching

```yaml
steps:
  - restore_cache:
      keys:
        # Try exact match first, then fall back to prefix
        - npm-deps-{{ checksum "package-lock.json" }}
        - npm-deps-

  - run: npm ci

  - save_cache:
      key: npm-deps-{{ checksum "package-lock.json" }}
      paths:
        - ~/.npm
        - node_modules
```

**Cache key templates:**
- `{{ checksum "file" }}` — hash of file contents
- `{{ .Branch }}` — current branch name
- `{{ .Revision }}` — git commit SHA
- `{{ epoch }}` — current timestamp (effectively disables caching)

---

## Test Parallelism & Splitting

CircleCI's killer feature: split your test suite across multiple containers automatically.

```yaml
jobs:
  test:
    parallelism: 4    # spin up 4 containers running in parallel
    docker:
      - image: cimg/node:20.0
    steps:
      - checkout
      - install-deps
      - run:
          name: Run tests (split)
          command: |
            # CircleCI CLI splits test files across containers
            TEST_FILES=$(circleci tests glob "src/**/*.test.ts" | \
              circleci tests split --split-by=timings)
            npm test -- $TEST_FILES
      - store_test_results:
          path: ./test-results
```

With 4 containers and a 20-minute test suite, this runs in ~5 minutes. GitHub Actions needs a matrix build (which requires knowing test file names upfront) to achieve the same.

---

## Workflows — Branches, Tags, Manual Approval

```yaml
workflows:
  ci-cd:
    jobs:
      # Run on all branches
      - test

      # Run on main only, after tests pass
      - build-and-push:
          requires: [test]
          filters:
            branches:
              only: main

      # Deploy staging automatically
      - deploy-staging:
          requires: [build-and-push]
          filters:
            branches:
              only: main

      # Manual approval gate before prod
      - approve-prod:
          type: approval
          requires: [deploy-staging]
          filters:
            branches:
              only: main

      - deploy-prod:
          requires: [approve-prod]
          filters:
            branches:
              only: main

      # Deploy to prod on version tags only
      - deploy-prod-from-tag:
          requires: [test]
          filters:
            tags:
              only: /^v.*/
            branches:
              ignore: /.*/
```

---

## Contexts — Shared Secrets Across Projects

Contexts let you share secrets across multiple CircleCI projects (similar to GitHub Organisation secrets).

```yaml
# In .circleci/config.yml
jobs:
  deploy:
    steps:
      - run: ./deploy.sh
    environment:
      AWS_REGION: ap-south-1

workflows:
  ci-cd:
    jobs:
      - deploy:
          context:
            - aws-prod-context     # load secrets from this context
            - slack-notifications  # can use multiple contexts
```

Set context secrets in CircleCI UI → Organisation Settings → Contexts.

---

## OIDC in CircleCI

CircleCI also supports OIDC for AWS authentication (no stored access keys):

```yaml
jobs:
  deploy:
    docker:
      - image: cimg/aws:2024.03
    steps:
      - checkout
      - run:
          name: Configure AWS via OIDC
          command: |
            # CircleCI sets CIRCLE_OIDC_TOKEN automatically
            aws sts assume-role-with-web-identity \
              --role-arn $AWS_ROLE_ARN \
              --role-session-name circleci-$CIRCLE_BUILD_NUM \
              --web-identity-token $CIRCLE_OIDC_TOKEN \
              --query 'Credentials' > /tmp/creds.json

            # Export credentials
            export AWS_ACCESS_KEY_ID=$(jq -r .AccessKeyId /tmp/creds.json)
            export AWS_SECRET_ACCESS_KEY=$(jq -r .SecretAccessKey /tmp/creds.json)
            export AWS_SESSION_TOKEN=$(jq -r .SessionToken /tmp/creds.json)

            # Now AWS CLI works with temporary credentials
            aws ecr get-login-password | docker login ...
```

The CircleCI OIDC trust policy condition uses:
```
"token.actions.githubusercontent.com:sub": "org/CIRCLECI_ORG_ID/project/CIRCLECI_PROJECT_ID/user/CIRCLECI_USER_ID"
```

---

## Key Insight for DevOps

Docker Layer Caching (`docker_layer_caching: true`) is the main reason to choose CircleCI over GitHub Actions for Docker-heavy pipelines. With DLC, unchanged layers are reused from previous builds stored on CircleCI's infrastructure — not the GitHub cache, which is per-repo and has a 10GB limit. For large images this can cut build times from 10 minutes to under 2.

The tradeoff: DLC requires the `machine` executor (a full VM), which is slower to start than the `docker` executor. For small images or fast builds, GitHub Actions with `cache-from: type=gha` is simpler and good enough.
