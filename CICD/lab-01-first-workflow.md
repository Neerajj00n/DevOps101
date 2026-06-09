# Lab 01 — Your First GitHub Actions Workflow

**Goal:** Write a real GitHub Actions workflow that lints, tests, and gives you feedback on every push and PR.

**Time:** ~30 minutes  
**Prerequisites:** A GitHub repo with a simple app (Node, Python, or Go). If you do not have one, create a new repo and add a basic app with a test file.

---

## Part 1 — Create the Workflow File

In your repo, create `.github/workflows/ci.yml`:

```yaml
name: CI

on:
  push:
    branches: [main, develop]
  pull_request:
    branches: [main]

jobs:
  lint-and-test:
    name: Lint and Test
    runs-on: ubuntu-latest

    steps:
      - name: Checkout code
        uses: actions/checkout@v4

      - name: Set up Node.js
        uses: actions/setup-node@v4
        with:
          node-version: '20'
          cache: 'npm'          # built-in caching for npm

      - name: Install dependencies
        run: npm ci

      - name: Run linter
        run: npm run lint

      - name: Run tests
        run: npm test

      - name: Upload test coverage
        uses: actions/upload-artifact@v4
        if: always()            # upload even if tests fail
        with:
          name: coverage-report
          path: ./coverage/
          retention-days: 7
```

Push this file and watch the Actions tab in GitHub.

---

## Part 2 — Add a Status Badge to Your README

Go to Actions tab → your workflow → click the three dots → "Create status badge" → copy the markdown.

Add it to your `README.md`:
```markdown
![CI](https://github.com/YOUR_ORG/YOUR_REPO/actions/workflows/ci.yml/badge.svg)
```

---

## Part 3 — Understand the Run

After the workflow runs:

1. Click into the run — examine each step's output and timing.
2. Which step took the longest?
3. Click "Re-run jobs" — how long does it take the second time with the npm cache?

---

## Part 4 — Make a PR

1. Create a new branch: `git checkout -b feature/test-ci`
2. Push a commit that introduces a linting error
3. Open a PR to `main`
4. Watch the CI check fail on the PR

Now fix the error, push again, and watch it pass. This is the feedback loop CI creates.

---

## Part 5 — Add a Second Job

Extend the workflow to run on multiple Node versions:

```yaml
jobs:
  lint-and-test:
    name: Test (Node ${{ matrix.node }})
    runs-on: ubuntu-latest

    strategy:
      matrix:
        node: [18, 20]
      fail-fast: false

    steps:
      - uses: actions/checkout@v4
      - uses: actions/setup-node@v4
        with:
          node-version: ${{ matrix.node }}
          cache: 'npm'
      - run: npm ci
      - run: npm test
```

Push and confirm two parallel jobs appear in the run.

---

## What You Should Now Understand

- How workflow files are structured and where they live
- How triggers control when workflows run
- How jobs and steps relate to each other
- How to read workflow run output and timings
- How CI creates a feedback loop on PRs

---

## Next Lab

[Lab 02 — Docker Pipeline with ECR →](./lab-02-docker-pipeline.md)
