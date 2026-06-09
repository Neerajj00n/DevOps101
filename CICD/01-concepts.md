# CI/CD Concepts & Pipeline Design

CI/CD is not a tool — it is a practice. The tool (GitHub Actions, CircleCI, Jenkins) is secondary to understanding *what* a pipeline should do and *why*.

---

## Definitions

**CI — Continuous Integration**
Every developer merges code to the main branch frequently (at least daily). Each merge triggers automated builds and tests. The goal: catch integration problems early, when they are cheap to fix.

**CD — Continuous Delivery**
Every successful CI run produces an artifact (Docker image, binary, package) that *could* be deployed to production. Deployment itself may still be manual or gated.

**CD — Continuous Deployment**
Every successful CI run automatically deploys to production. No human gate. Requires high confidence in your test suite and rollback mechanisms.

Most teams practice Continuous Delivery, not Continuous Deployment. The distinction matters when you are designing your pipeline.

---

## What a Pipeline Is

A pipeline is a sequence of automated steps that code passes through before it reaches users. Each step is a gate — if it fails, the pipeline stops.

```
Code Push
    │
    ▼
┌─────────────┐
│   Trigger   │  ← what event starts the pipeline
└──────┬──────┘
       │
    ┌──▼──────────────┐
    │  Checkout code  │
    └──┬──────────────┘
       │
    ┌──▼──────────────┐
    │  Install deps   │  ← cached for speed
    └──┬──────────────┘
       │
    ┌──▼──────────────┐
    │  Lint / Format  │  ← fast, cheap — fail early
    └──┬──────────────┘
       │
    ┌──▼──────────────┐
    │  Unit Tests     │  ← no external dependencies
    └──┬──────────────┘
       │
    ┌──▼──────────────┐
    │ Integration     │  ← may need DB, cache, etc.
    │    Tests        │
    └──┬──────────────┘
       │
    ┌──▼──────────────┐
    │  Build Docker   │  ← only if tests pass
    │     Image       │
    └──┬──────────────┘
       │
    ┌──▼──────────────┐
    │  Push to ECR    │  ← only on main branch
    └──┬──────────────┘
       │
    ┌──▼──────────────┐
    │ Deploy Staging  │  ← automatic
    └──┬──────────────┘
       │
    ┌──▼──────────────┐
    │  Manual Gate    │  ← human approval
    └──┬──────────────┘
       │
    ┌──▼──────────────┐
    │  Deploy Prod    │
    └─────────────────┘
```

**Rule:** Put cheap, fast checks first. Linting costs 10 seconds. If it fails, you have saved the 5 minutes a Docker build would have taken.

---

## Pipeline Triggers

What starts a pipeline matters as much as what it does.

```
Push to any branch       → lint + test (fast feedback)
Push to main             → lint + test + build + push + deploy staging
Pull request opened      → lint + test + optional preview environment
Release tag (v*)         → build + push + deploy prod (with approval)
Schedule (cron)          → nightly integration tests, security scans
Manual (workflow_dispatch) → on-demand deploys, rollbacks
```

---

## Branching Strategies

Your branching strategy determines when pipelines run and what they do.

**GitHub Flow** (simple, recommended for most teams)
```
main ─────────────────────────────────── (always deployable)
         └── feature/x ──► PR ──► merge
```
- All work happens in short-lived feature branches
- PR triggers CI (lint + test)
- Merge to main triggers deploy to staging
- Release tag triggers deploy to prod

**GitFlow** (complex, useful for scheduled releases)
```
main ──────────────────────────────────── (prod)
develop ───────────────────────────────── (staging)
          └── feature/x ──► PR ──► merge to develop
                    release/1.0 ──► merge to main + tag
```
- More structure, more overhead
- Useful when you have fixed release cycles

For most DevOps setups: **use GitHub Flow**. GitFlow adds complexity without proportional benefit unless you have strict release windows.

---

## Artifact Strategy

Every pipeline run should produce a versioned, immutable artifact.

```bash
# Bad — tag always moves, hard to trace what is deployed
docker push myapp:latest

# Good — Git SHA is immutable, always traceable
IMAGE_TAG=$(git rev-parse --short HEAD)
docker push myapp:${IMAGE_TAG}
docker push myapp:latest   # also push latest for convenience, but deploy by SHA
```

Always deploy by SHA. `latest` is for humans browsing registries, not for pipelines deploying to production.

---

## GitHub Actions vs CircleCI — When to Use Which

| | GitHub Actions | CircleCI |
|---|---|---|
| **Best for** | GitHub-native projects, OSS | Complex pipelines, fine-grained control |
| **Pricing** | Free for public repos, minutes-based for private | Free tier generous, credit-based |
| **Docker support** | Good via `docker buildx` | Excellent, Docker Layer Caching native |
| **Parallelism** | Matrix builds | Fan-out jobs, test splitting |
| **Self-hosted runners** | Yes | Yes (via resource classes) |
| **Pipeline as code** | YAML in `.github/workflows/` | YAML in `.circleci/config.yml` |
| **Ecosystem** | Massive marketplace of Actions | Orbs (reusable packages) |
| **Secret management** | GitHub Secrets + Environments | Project/Context-level secrets |

**Practical answer:** If your code is on GitHub, start with GitHub Actions. Add CircleCI if you need its specific strengths (Docker Layer Caching, advanced test splitting, or your team has existing CircleCI knowledge).

---

## Pipeline Security Principles

1. **Never store cloud credentials as long-lived secrets.** Use OIDC (OpenID Connect) to get temporary credentials from AWS per pipeline run. No stored access keys.

2. **Least privilege for pipeline roles.** The IAM role your pipeline assumes should have only the permissions it needs — push to ECR, deploy to ECS, nothing else.

3. **Pin action versions by SHA, not tag.** Tags can be moved. SHAs cannot.
   ```yaml
   # Bad — tag can be updated by the action author
   uses: actions/checkout@v4
   # Good — SHA is immutable
   uses: actions/checkout@11bd71901bbe5b1630ceea73d27597364c9af683
   ```

4. **Never print secrets in logs.** GitHub Actions masks secrets automatically, but `set -x` in a bash step will print them. Use `set +x` before commands that touch secrets.

5. **Separate staging and prod secrets.** Use GitHub Environments with environment-specific secrets so staging pipelines cannot accidentally touch prod credentials.

---

## Key Insight for DevOps

A pipeline that takes 20 minutes gives developers 20-minute feedback loops. They will start batching changes, working around the pipeline, or ignoring failures. Keep pipelines under 10 minutes for the critical path (lint + test + build). Anything slower goes in a separate nightly or weekly workflow.
