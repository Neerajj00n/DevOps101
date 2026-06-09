# Pipeline Optimisation

A slow pipeline is a tax on every developer every day. If CI takes 20 minutes, a 10-person team loses over 3 hours of developer time per day just waiting. These are the techniques that actually move the needle.

---

## Measure Before Optimising

Before changing anything, know your baseline:

```bash
# GitHub Actions — check run times in the UI
# Actions tab → workflow run → see per-job and per-step timing

# Or via CLI
gh run list --workflow=ci.yml --limit=10 --json databaseId,conclusion,createdAt,updatedAt
```

Identify: which job takes the longest? Which step within that job? That is where to focus.

---

## Dependency Caching

The single biggest win for most pipelines. Cache your package manager's download cache between runs.

**GitHub Actions:**

```yaml
- name: Cache npm
  uses: actions/cache@v4
  with:
    path: ~/.npm
    key: npm-${{ runner.os }}-${{ hashFiles('**/package-lock.json') }}
    restore-keys: |
      npm-${{ runner.os }}-

- run: npm ci
```

```yaml
# Python
- uses: actions/cache@v4
  with:
    path: ~/.cache/pip
    key: pip-${{ runner.os }}-${{ hashFiles('**/requirements.txt') }}
- run: pip install -r requirements.txt

# Go
- uses: actions/cache@v4
  with:
    path: ~/go/pkg/mod
    key: go-${{ runner.os }}-${{ hashFiles('**/go.sum') }}
- run: go mod download
```

**Key structure matters:**
```
key: npm-${{ runner.os }}-${{ hashFiles('package-lock.json') }}
     │        │                  │
     prefix   OS               lockfile hash — changes when deps change

restore-keys: |
  npm-${{ runner.os }}-    ← fallback: use any cache for this OS
  npm-                     ← further fallback
```

Cache hits save 1–3 minutes per run for typical projects.

---

## Docker Layer Caching

Order your Dockerfile to maximise cache reuse. Layers only rebuild from the point where something changes.

```dockerfile
# Bad — COPY . happens early, invalidates everything below it on any code change
FROM node:20-alpine
WORKDIR /app
COPY . .                    # any code change = cache miss here
RUN npm ci                  # re-runs every time even if deps unchanged
RUN npm run build

# Good — deps installed before code is copied
FROM node:20-alpine
WORKDIR /app
COPY package*.json ./       # only invalidates if package.json changes
RUN npm ci                  # cached unless deps changed
COPY . .                    # code changes here only rebuild this layer and below
RUN npm run build
```

**In GitHub Actions:**
```yaml
- uses: docker/build-push-action@v5
  with:
    cache-from: type=gha
    cache-to: type=gha,mode=max
```

---

## Parallelism — Run Jobs Simultaneously

```yaml
jobs:
  lint:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - run: npm run lint

  test:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - run: npm test

  typecheck:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - run: npm run typecheck

  # Build only after all three pass
  build:
    needs: [lint, test, typecheck]
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - run: docker build .
```

Lint + test + typecheck run simultaneously. If each takes 3 minutes, total time is 3 minutes (not 9).

---

## Matrix Builds — Test Multiple Versions

```yaml
jobs:
  test:
    strategy:
      matrix:
        python-version: ['3.11', '3.12']
        os: [ubuntu-latest, macos-latest]
      fail-fast: false    # let all matrix jobs complete even if one fails

    runs-on: ${{ matrix.os }}

    steps:
      - uses: actions/checkout@v4
      - uses: actions/setup-python@v5
        with:
          python-version: ${{ matrix.python-version }}
      - run: pip install -r requirements.txt && pytest
```

This creates 4 parallel jobs (2 Python versions × 2 OS). All run simultaneously.

---

## Skip Unnecessary Work

**Path filtering** — only run the pipeline if relevant files changed:

```yaml
on:
  push:
    paths:
      - 'src/**'
      - 'tests/**'
      - 'Dockerfile'
      - 'requirements.txt'
    paths-ignore:
      - '**.md'
      - 'docs/**'
      - '.github/CODEOWNERS'
```

**Conditional steps** — skip expensive steps when not needed:

```yaml
steps:
  # Only build and push Docker image on main branch
  - name: Build and push
    if: github.ref == 'refs/heads/main'
    uses: docker/build-push-action@v5
    with:
      push: true
      ...

  # Only deploy to prod on version tags
  - name: Deploy to prod
    if: startsWith(github.ref, 'refs/tags/v')
    run: ./deploy-prod.sh
```

**Concurrency** — cancel in-progress runs when a new commit is pushed:

```yaml
concurrency:
  group: ${{ github.workflow }}-${{ github.ref }}
  cancel-in-progress: true
```

This prevents 5 queued pipeline runs piling up when a developer pushes 5 commits quickly. Each new push cancels the previous run.

---

## Fail Fast — Cheap Checks First

Order your steps so the fastest, cheapest checks run first:

```yaml
steps:
  - uses: actions/checkout@v4

  # 1. Format check — < 5 seconds
  - run: npm run format:check

  # 2. Linting — < 30 seconds
  - run: npm run lint

  # 3. Type check — < 1 minute
  - run: npm run typecheck

  # 4. Unit tests — 1-3 minutes
  - run: npm run test:unit

  # 5. Integration tests — 3-10 minutes
  - run: npm run test:integration

  # 6. Build Docker image — 2-5 minutes (only if tests pass)
  - run: docker build .
```

A formatting error fails in 5 seconds instead of waiting 10 minutes for integration tests.

---

## Reuse Across Workflows (Avoid Re-running Setup)

Share build artifacts between jobs instead of rebuilding:

```yaml
jobs:
  build:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - run: npm ci && npm run build
      - uses: actions/upload-artifact@v4
        with:
          name: dist
          path: ./dist
          retention-days: 1

  test-e2e:
    needs: build
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: actions/download-artifact@v4
        with:
          name: dist
          path: ./dist
      - run: npm run test:e2e    # uses the built artifact, no rebuild
```

---

## Benchmark: Before vs After

A typical pipeline optimisation result:

| Stage | Before | After |
|-------|--------|-------|
| Install deps | 3:20 | 0:15 (cached) |
| Lint | sequential | parallel |
| Tests | sequential | parallel |
| Docker build | 8:00 | 1:30 (layer cache) |
| **Total** | **~18 min** | **~4 min** |

---

## Key Insight for DevOps

Caching is almost always the highest-ROI optimisation. Check your cache hit rate — GitHub Actions shows this in the cache action step output. A low hit rate means your cache keys are wrong (too specific, invalidating on every run). A hit rate above 80% is healthy.

After caching, the next biggest win is parallelism. Most pipelines run lint → test → build sequentially when they could run lint and test in parallel, then build.
