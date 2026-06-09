# Lab 04 — CircleCI Pipeline

**Goal:** Replicate your GitHub Actions CI pipeline in CircleCI and understand the key differences.

**Time:** ~45 minutes  
**Prerequisites:** Lab 01 and 02 complete. A CircleCI account (free tier is sufficient — sign in with GitHub).

---

## Part 1 — Connect Your Repo

1. Go to [circleci.com](https://circleci.com) → Sign in with GitHub
2. Click "Projects" → Find your repo → Click "Set Up Project"
3. Choose "Fastest" (use existing config) or start from scratch

---

## Part 2 — Basic CI Config

Create `.circleci/config.yml`:

```yaml
version: 2.1

orbs:
  node: circleci/node@5.0

jobs:
  lint-and-test:
    executor: node/default
    steps:
      - checkout
      - node/install-packages:
          pkg-manager: npm
      - run:
          name: Lint
          command: npm run lint
      - run:
          name: Test
          command: npm test
      - store_test_results:
          path: ./test-results
      - store_artifacts:
          path: ./coverage
          destination: coverage

workflows:
  ci:
    jobs:
      - lint-and-test
```

Push this and watch the pipeline run in the CircleCI dashboard.

---

## Part 3 — Add Docker Build and ECR Push

Set project-level environment variables in CircleCI UI (Project Settings → Environment Variables):
- `AWS_REGION` = `ap-south-1`
- `AWS_ACCOUNT_ID` = your account ID
- `ECR_REPO` = `myapp`

For OIDC, set:
- `AWS_ROLE_ARN` = your GitHub Actions role ARN (or create a separate CircleCI role)

```yaml
version: 2.1

orbs:
  node: circleci/node@5.0
  aws-cli: circleci/aws-cli@4.0

jobs:
  lint-and-test:
    executor: node/default
    steps:
      - checkout
      - node/install-packages:
          pkg-manager: npm
      - run: npm run lint
      - run: npm test
      - store_test_results:
          path: ./test-results

  build-and-push:
    machine:
      image: ubuntu-2204:current
      docker_layer_caching: true    # CircleCI's DLC — faster than GitHub cache for Docker
    steps:
      - checkout
      - aws-cli/setup
      - run:
          name: Authenticate with ECR
          command: |
            ECR_REGISTRY="${AWS_ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com"
            aws ecr get-login-password --region $AWS_REGION | \
              docker login --username AWS --password-stdin $ECR_REGISTRY
      - run:
          name: Build and push
          command: |
            ECR_REGISTRY="${AWS_ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com"
            IMAGE_TAG=$(git rev-parse --short HEAD)

            docker build -t $ECR_REGISTRY/$ECR_REPO:$IMAGE_TAG .
            docker push $ECR_REGISTRY/$ECR_REPO:$IMAGE_TAG

            docker tag $ECR_REGISTRY/$ECR_REPO:$IMAGE_TAG \
                       $ECR_REGISTRY/$ECR_REPO:latest
            docker push $ECR_REGISTRY/$ECR_REPO:latest

            echo "Pushed: $ECR_REGISTRY/$ECR_REPO:$IMAGE_TAG"

workflows:
  ci-cd:
    jobs:
      - lint-and-test
      - build-and-push:
          requires:
            - lint-and-test
          filters:
            branches:
              only: main      # only run on main branch
```

---

## Part 4 — Add Manual Approval for Production

```yaml
workflows:
  ci-cd:
    jobs:
      - lint-and-test

      - build-and-push:
          requires: [lint-and-test]
          filters:
            branches:
              only: main

      - deploy-staging:
          requires: [build-and-push]
          filters:
            branches:
              only: main

      - approve-production:
          type: approval          # pauses pipeline, waits for human click
          requires: [deploy-staging]
          filters:
            branches:
              only: main

      - deploy-production:
          requires: [approve-production]
          filters:
            branches:
              only: main
```

After deploying to staging, CircleCI will pause the pipeline. You will see an "Approve" button in the dashboard. Click it to proceed to production.

---

## Part 5 — Compare GitHub Actions vs CircleCI

Fill in this table based on your experience with both:

| Feature | GitHub Actions (your experience) | CircleCI (your experience) |
|---------|----------------------------------|---------------------------|
| Config location | | |
| Time to first run | | |
| Cache hit speed | | |
| Docker build time | | |
| UI clarity | | |
| Debugging failed runs | | |
| Secret management | | |
| Manual approval flow | | |

There is no right answer. The point is to have direct experience with both.

---

## Tasks to Complete

1. Get the basic `lint-and-test` job passing in CircleCI.
2. Add the `build-and-push` job and confirm images appear in ECR.
3. Add the manual approval step and practice approving a production deploy.
4. Push a commit with a lint error — confirm CircleCI catches it and the build-and-push job does not run.
5. Compare the Docker build time between CircleCI (with DLC) and GitHub Actions (with GHA cache).

---

## What You Should Now Understand

- The structural differences between GitHub Actions and CircleCI YAML
- How CircleCI's `requires` maps to GitHub Actions' `needs`
- How CircleCI's `type: approval` implements manual gates
- What Docker Layer Caching means and when it matters
- When to use each platform

---

## Next Lab

[Lab 05 — Pipeline Optimisation →](./lab-05-optimise.md)
