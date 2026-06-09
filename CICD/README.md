# 05 — CI/CD Pipelines

> Every code change should go through an automated pipeline before it touches production. No exceptions. This module covers how to build those pipelines — from a simple lint check to a full build → test → push → deploy workflow using GitHub Actions and CircleCI.

---

## 🎯 What You'll Learn

- Understand CI/CD concepts and pipeline design principles
- Write GitHub Actions workflows from scratch
- Build, test, and push Docker images in CI
- Manage secrets properly — never hardcode credentials
- Use reusable workflows and composite actions to avoid duplication
- Set up CircleCI as a second CI platform (and understand when to use which)
- Design branching strategies that work with automated pipelines
- Optimise pipelines with caching and parallelism

---

## ✅ Prerequisites

[04 — Docker](../04-docker/) — Pipelines build and push Docker images. Know Docker first.
[03 — Terraform](../03-terraform/) — Helpful for understanding the infra pipelines deploy to.

---

## 📚 Notes

| Topic | File |
|-------|------|
| CI/CD Concepts & Pipeline Design | [01-concepts.md](./notes/01-concepts.md) |
| GitHub Actions — Core Syntax | [02-gha-basics.md](./notes/02-gha-basics.md) |
| GitHub Actions — Docker & ECR | [03-gha-docker.md](./notes/03-gha-docker.md) |
| GitHub Actions — Secrets & OIDC | [04-secrets-oidc.md](./notes/04-secrets-oidc.md) |
| GitHub Actions — Reusable Workflows | [05-reusable-workflows.md](./notes/05-reusable-workflows.md) |
| CircleCI | [06-circleci.md](./notes/06-circleci.md) |
| Pipeline Optimisation | [07-optimisation.md](./notes/07-optimisation.md) |

---

## 🧪 Labs

| Lab | Description |
|-----|-------------|
| [Lab 01](./labs/lab-01-first-workflow.md) | Write your first GitHub Actions workflow — lint and test on push |
| [Lab 02](./labs/lab-02-docker-pipeline.md) | Build a Docker image in CI and push it to ECR using OIDC |
| [Lab 03](./labs/lab-03-multi-env.md) | Deploy to staging on PR merge, prod on release tag |
| [Lab 04](./labs/lab-04-circleci.md) | Replicate your GitHub Actions pipeline in CircleCI |
| [Lab 05](./labs/lab-05-optimise.md) | Add caching, parallelism, and conditional steps to a pipeline |

---

## 🔧 Module Project

**Build a complete CI/CD pipeline for a Dockerised web app.**

The pipeline will:
- Trigger on push to `main` and on pull requests
- Run linting and tests on every PR
- Build and push a Docker image to ECR on merge to `main`
- Tag the image with the Git SHA and `latest`
- Authenticate to AWS using OIDC (no stored access keys)
- Deploy to a staging environment automatically
- Require manual approval before deploying to production
- Notify on failure via Slack webhook

Full solution in [solutions/full-pipeline/](./solutions/full-pipeline/)

---

## 🔧 Example Workflows

Complete example workflow files for CI/CD pipelines:

| File | Description |
|------|-------------|
| [github-actions.yml](./examples/workflows/github-actions.yml) | Full GitHub Actions pipeline with build, test, deploy to staging/production |
| [circleci-config.yml](./examples/workflows/circleci-config.yml) | Complete CircleCI configuration with approval gates and notifications |

---

## ⬅️ Previous | ➡️ Next

[← 04 Docker](../04-docker/) | [06 Kubernetes →](../06-kubernetes/)
