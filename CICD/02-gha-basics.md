# GitHub Actions — Core Syntax

GitHub Actions workflows live in `.github/workflows/` in your repo. Every `.yml` file in that directory is a separate workflow. GitHub reads them automatically — no registration needed.

---

## Anatomy of a Workflow

```yaml
name: CI                          # displayed in GitHub UI

on:                               # triggers
  push:
    branches: [main, develop]
  pull_request:
    branches: [main]
  workflow_dispatch:              # manual trigger via UI or API

env:                              # workflow-level environment variables
  NODE_VERSION: "20"
  AWS_REGION: ap-south-1

jobs:
  test:                           # job ID (used for dependencies)
    name: Run Tests               # displayed name (optional)
    runs-on: ubuntu-latest        # runner OS

    steps:
      - name: Checkout code
        uses: actions/checkout@v4

      - name: Set up Node
        uses: actions/setup-node@v4
        with:
          node-version: ${{ env.NODE_VERSION }}

      - name: Install dependencies
        run: npm ci

      - name: Run tests
        run: npm test

  build:
    name: Build Docker Image
    runs-on: ubuntu-latest
    needs: test                   # only runs if 'test' job passes

    steps:
      - uses: actions/checkout@v4
      - name: Build image
        run: docker build -t myapp .
```

---

## Triggers (`on`)

```yaml
on:
  # Push to specific branches
  push:
    branches:
      - main
      - 'release/**'        # glob pattern
    paths:
      - 'src/**'            # only trigger if these paths changed
      - 'Dockerfile'
    paths-ignore:
      - '**.md'             # ignore docs changes

  # PRs targeting specific branches
  pull_request:
    branches: [main]
    types: [opened, synchronize, reopened]

  # On a schedule (cron syntax)
  schedule:
    - cron: '0 2 * * 1-5'  # 2am UTC, Mon-Fri

  # Manual trigger
  workflow_dispatch:
    inputs:
      environment:
        description: 'Deploy to which environment'
        required: true
        default: 'staging'
        type: choice
        options: [staging, prod]

  # Called by another workflow
  workflow_call:
    inputs:
      image-tag:
        required: true
        type: string
```

---

## Jobs & Steps

```yaml
jobs:
  my-job:
    runs-on: ubuntu-latest

    # Run on multiple OS/versions simultaneously
    strategy:
      matrix:
        os: [ubuntu-latest, macos-latest]
        node: [18, 20]
      fail-fast: false    # don't cancel all matrix jobs if one fails

    runs-on: ${{ matrix.os }}

    steps:
      # Use a community action
      - uses: actions/checkout@v4
        with:
          fetch-depth: 0    # full history (needed for some tools)

      # Run a shell command
      - name: Run script
        run: |
          echo "Multi-line"
          echo "shell script"
        shell: bash
        working-directory: ./src
        env:
          MY_VAR: "value"       # step-level env var

      # Conditional step
      - name: Only on main
        if: github.ref == 'refs/heads/main'
        run: echo "This is main branch"

      # Conditional on previous step outcome
      - name: On failure only
        if: failure()
        run: echo "Something failed"

      # Save output for later steps
      - name: Get version
        id: version
        run: echo "tag=$(git describe --tags)" >> $GITHUB_OUTPUT

      - name: Use the output
        run: echo "Version is ${{ steps.version.outputs.tag }}"
```

---

## Contexts & Expressions

```yaml
# github context — repo and event info
${{ github.sha }}               # full commit SHA
${{ github.ref }}               # refs/heads/main
${{ github.ref_name }}          # main
${{ github.actor }}             # who triggered the run
${{ github.repository }}        # owner/repo-name
${{ github.event_name }}        # push, pull_request, etc.
${{ github.event.pull_request.number }}

# runner context
${{ runner.os }}                # Linux, macOS, Windows
${{ runner.temp }}              # temp directory

# env context
${{ env.MY_VAR }}

# secrets context (never printed in logs)
${{ secrets.MY_SECRET }}

# needs context — outputs from other jobs
${{ needs.build.outputs.image-tag }}

# Conditional expressions
if: github.event_name == 'push'
if: github.ref == 'refs/heads/main'
if: contains(github.event.pull_request.labels.*.name, 'deploy')
if: startsWith(github.ref, 'refs/tags/v')
if: failure() || cancelled()
if: always()                    # run even if previous steps failed
```

---

## Setting Outputs & Environment Variables

```yaml
steps:
  # Set output for other steps in this job
  - id: build
    run: |
      IMAGE_TAG=$(git rev-parse --short HEAD)
      echo "image-tag=${IMAGE_TAG}" >> $GITHUB_OUTPUT

  # Use it in later step
  - run: echo "Built ${{ steps.build.outputs.image-tag }}"

  # Set env var for later steps in this job
  - run: echo "IMAGE_TAG=$(git rev-parse --short HEAD)" >> $GITHUB_ENV

  - run: echo "Tag is $IMAGE_TAG"    # available in subsequent steps

  # Append to PATH
  - run: echo "/my/tool/bin" >> $GITHUB_PATH
```

---

## Job Outputs (between jobs)

```yaml
jobs:
  build:
    outputs:
      image-tag: ${{ steps.tag.outputs.value }}
    steps:
      - id: tag
        run: echo "value=$(git rev-parse --short HEAD)" >> $GITHUB_OUTPUT

  deploy:
    needs: build
    steps:
      - run: echo "Deploying ${{ needs.build.outputs.image-tag }}"
```

---

## Permissions

GitHub Actions tokens have broad permissions by default. Lock them down:

```yaml
# Global — applies to all jobs
permissions:
  contents: read        # read repo code
  id-token: write       # needed for OIDC (AWS auth)
  packages: write       # push to GitHub Container Registry

# Or per-job
jobs:
  deploy:
    permissions:
      id-token: write
      contents: read
```

**Minimum permissions for common tasks:**
- Checkout only: `contents: read`
- OIDC (AWS): `id-token: write` + `contents: read`
- Push to GHCR: `packages: write` + `contents: read`
- Create PR comment: `pull-requests: write`

---

## Useful Built-in Actions

```yaml
# Checkout
- uses: actions/checkout@v4

# Language runtimes
- uses: actions/setup-node@v4
  with: { node-version: '20' }
- uses: actions/setup-python@v5
  with: { python-version: '3.12' }
- uses: actions/setup-go@v5
  with: { go-version: '1.22' }

# Caching (covered in optimisation notes)
- uses: actions/cache@v4

# Upload/download artifacts between jobs
- uses: actions/upload-artifact@v4
  with:
    name: test-results
    path: ./coverage/
- uses: actions/download-artifact@v4
  with:
    name: test-results

# GitHub script (run JS in the workflow)
- uses: actions/github-script@v7
  with:
    script: |
      github.rest.issues.createComment({
        issue_number: context.issue.number,
        owner: context.repo.owner,
        repo: context.repo.repo,
        body: 'Deploy succeeded!'
      })
```

---

## Key Insight for DevOps

`$GITHUB_OUTPUT`, `$GITHUB_ENV`, and `$GITHUB_PATH` replaced the old `::set-output::` / `::set-env::` syntax. If you see old tutorials using those, they are outdated and will produce deprecation warnings. Always use the file-based approach shown above.
