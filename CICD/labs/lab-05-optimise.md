# Lab 05: Optimize Your CI/CD Pipeline

In this lab, you'll learn techniques to make your CI/CD pipeline faster and more efficient by implementing caching, parallelism, and conditional steps.

## Objectives

- Implement caching strategies to speed up builds
- Run tests in parallel to reduce pipeline execution time
- Add conditional steps to skip unnecessary work
- Measure and compare pipeline performance before and after optimizations

## Prerequisites

- Completed Lab 01 and Lab 02
- A GitHub repository with a CI/CD pipeline

## Lab Steps

### 1. Analyze Your Current Pipeline

Before optimizing, gather baseline metrics:

1. Run your existing pipeline and note the total execution time
2. Identify the slowest steps in your workflow
3. Look for steps that could be cached or parallelized

### 2. Implement Dependency Caching

Add caching for package managers to avoid repeatedly downloading the same dependencies:

For Node.js projects:
```yaml
- name: Cache Node.js modules
  uses: actions/cache@v3
  with:
    path: ~/.npm
    key: ${{ runner.os }}-node-${{ hashFiles('**/package-lock.json') }}
    restore-keys: |
      ${{ runner.os }}-node-
```

For Python projects:
```yaml
- name: Cache pip packages
  uses: actions/cache@v3
  with:
    path: ~/.cache/pip
    key: ${{ runner.os }}-pip-${{ hashFiles('**/requirements.txt') }}
    restore-keys: |
      ${{ runner.os }}-pip-
```

### 3. Cache Docker Layers

Add caching for Docker builds to reuse layers:

```yaml
- name: Set up Docker Buildx
  uses: docker/setup-buildx-action@v2

- name: Cache Docker layers
  uses: actions/cache@v3
  with:
    path: /tmp/.buildx-cache
    key: ${{ runner.os }}-buildx-${{ github.sha }}
    restore-keys: |
      ${{ runner.os }}-buildx-

- name: Build and push Docker image
  uses: docker/build-push-action@v4
  with:
    context: .
    push: true
    tags: ${{ env.IMAGE_NAME }}:${{ github.sha }}
    cache-from: type=local,src=/tmp/.buildx-cache
    cache-to: type=local,dest=/tmp/.buildx-cache-new,mode=max
```

### 4. Implement Test Parallelism

Split your test suite to run in parallel:

```yaml
jobs:
  test:
    runs-on: ubuntu-latest
    strategy:
      matrix:
        test-group: [unit, integration, e2e]
    steps:
      - uses: actions/checkout@v3
      
      - name: Set up Node.js
        uses: actions/setup-node@v3
        with:
          node-version: '16'
      
      - name: Install dependencies
        run: npm ci
      
      - name: Run tests
        run: npm test -- --group=${{ matrix.test-group }}
```

### 5. Add Conditional Steps

Add conditions to skip unnecessary steps:

```yaml
- name: Run linting
  if: github.event_name == 'pull_request'
  run: npm run lint

- name: Deploy to production
  if: startsWith(github.ref, 'refs/tags/v')
  run: ./deploy.sh production
```

### 6. Optimize CI Skip for Small Changes

Add the ability to skip CI for documentation-only changes:

```yaml
jobs:
  check-changes:
    runs-on: ubuntu-latest
    outputs:
      should_run: ${{ steps.filter.outputs.code == 'true' }}
    steps:
      - uses: actions/checkout@v3
      
      - uses: dorny/paths-filter@v2
        id: filter
        with:
          filters: |
            code:
              - '!**.md'
              - '!docs/**'
              - '!**/*.txt'
  
  build:
    needs: check-changes
    if: needs.check-changes.outputs.should_run == 'true'
    # Rest of the build job
```

### 7. Measure Improved Performance

After implementing these optimizations:

1. Run your pipeline again
2. Compare the execution time to your baseline
3. Document which optimizations had the biggest impact

## Extension Tasks

- Configure a self-hosted runner for even faster builds
- Implement artifact caching for build outputs between jobs
- Set up dependency updates with Dependabot to keep cached dependencies fresh
- Create a build status badge for your repository README

## Submission

Submit:
1. Your optimized workflow YAML file
2. Screenshots showing before and after pipeline execution times
3. A brief report on which optimizations were most effective for your project