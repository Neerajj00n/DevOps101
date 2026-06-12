# Helm — The Kubernetes Package Manager

Deploying even a simple application to Kubernetes requires multiple YAML files — a Deployment, a Service, a ConfigMap, maybe an Ingress and some Secrets. Managing all of these by hand across multiple environments (dev, staging, prod) quickly becomes unmaintainable. Helm solves this with templated, versioned, packageable applications called Charts.

---

## The Problem Helm Solves

```
Without Helm:
  - 8 separate YAML files per app
  - Duplicate manifests for dev/staging/prod with tiny differences
  - No way to version or rollback an application deployment
  - Installing third-party software (Prometheus, nginx-ingress) is tedious

With Helm:
  helm install prometheus prometheus-community/kube-prometheus-stack
  helm upgrade my-app ./my-chart --set image.tag=v2.0.0
  helm rollback my-app 1
```

---

## Core Concepts

| Term | Meaning |
|------|---------|
| **Chart** | A packaged application — templates + default values |
| **Release** | A deployed instance of a chart in the cluster |
| **Repository** | A collection of charts (like a package registry) |
| **Values** | Configuration that customizes a chart's templates |

You can install the same chart multiple times as different releases:
```bash
helm install prod-db bitnami/postgresql --set auth.password=prod123
helm install staging-db bitnami/postgresql --set auth.password=stage123
```

---

## Installation

```bash
# macOS
brew install helm

# Linux
curl https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash

# Verify
helm version
```

---

## Working with Repositories

```bash
# Add a repository
helm repo add bitnami https://charts.bitnami.com/bitnami
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
helm repo add ingress-nginx https://kubernetes.github.io/ingress-nginx

# Update repository index
helm repo update

# List repositories
helm repo list

# Search for charts
helm search repo nginx
helm search repo bitnami/postgres
helm search hub wordpress    # search Artifact Hub (public catalog)
```

---

## Installing and Managing Releases

```bash
# Install a chart
helm install my-release bitnami/nginx

# Install into a specific namespace (create if needed)
helm install my-release bitnami/nginx \
  --namespace web \
  --create-namespace

# Install with custom values
helm install my-db bitnami/postgresql \
  --set auth.postgresPassword=secret123 \
  --set primary.persistence.size=20Gi

# Install from a values file
helm install my-db bitnami/postgresql -f prod-values.yaml

# List releases
helm list
helm list -A          # all namespaces

# Upgrade a release
helm upgrade my-db bitnami/postgresql --set auth.postgresPassword=newpassword

# Upgrade or install if not exists
helm upgrade --install my-db bitnami/postgresql -f values.yaml

# Rollback to a previous revision
helm rollback my-db 1

# View release history
helm history my-db

# Uninstall a release
helm uninstall my-db
```

---

## Inspecting Charts

```bash
# Show chart info
helm show chart bitnami/postgresql

# Show all default values
helm show values bitnami/postgresql

# Show rendered templates without installing (dry run)
helm template my-release bitnami/postgresql -f my-values.yaml

# Test what would change on upgrade
helm upgrade --dry-run my-db bitnami/postgresql -f new-values.yaml
```

---

## Chart Structure

```
my-chart/
├── Chart.yaml          # chart metadata (name, version, description, dependencies)
├── values.yaml         # default configuration values
├── charts/             # chart dependencies (subcharts)
├── templates/          # Kubernetes manifests with Go template syntax
│   ├── deployment.yaml
│   ├── service.yaml
│   ├── ingress.yaml
│   ├── configmap.yaml
│   ├── _helpers.tpl    # template helpers (partials, named templates)
│   ├── NOTES.txt       # shown to user after helm install
│   └── tests/
│       └── test-connection.yaml
└── .helmignore         # files to ignore when packaging
```

---

## Creating Your Own Chart

```bash
# Scaffold a new chart
helm create my-app

# Validate chart structure
helm lint my-app/

# Render templates locally
helm template my-app ./my-app -f my-values.yaml
```

### Chart.yaml

```yaml
apiVersion: v2
name: my-app
description: A Helm chart for my application
type: application       # application or library
version: 0.1.0          # chart version (SemVer)
appVersion: "1.0.0"     # version of the app itself
dependencies:
- name: postgresql
  version: "15.5.x"
  repository: https://charts.bitnami.com/bitnami
  condition: postgresql.enabled   # only install if values.postgresql.enabled = true
```

### values.yaml

```yaml
replicaCount: 1

image:
  repository: nginx
  tag: "1.27-alpine"
  pullPolicy: IfNotPresent

service:
  type: ClusterIP
  port: 80

ingress:
  enabled: false
  host: myapp.example.com

resources:
  requests:
    cpu: 100m
    memory: 128Mi
  limits:
    cpu: 500m
    memory: 256Mi

postgresql:
  enabled: true
  auth:
    database: myapp
    username: myapp
    password: ""    # set via --set or secrets
```

### Templates with Go Templating

```yaml
# templates/deployment.yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: {{ include "my-app.fullname" . }}   # uses helper from _helpers.tpl
  labels:
    {{- include "my-app.labels" . | nindent 4 }}
spec:
  replicas: {{ .Values.replicaCount }}       # from values.yaml
  selector:
    matchLabels:
      {{- include "my-app.selectorLabels" . | nindent 6 }}
  template:
    metadata:
      labels:
        {{- include "my-app.selectorLabels" . | nindent 8 }}
    spec:
      containers:
      - name: {{ .Chart.Name }}
        image: "{{ .Values.image.repository }}:{{ .Values.image.tag }}"
        imagePullPolicy: {{ .Values.image.pullPolicy }}
        ports:
        - containerPort: {{ .Values.service.port }}
        resources:
          {{- toYaml .Values.resources | nindent 10 }}
        {{- if .Values.ingress.enabled }}
        env:
        - name: BASE_URL
          value: "https://{{ .Values.ingress.host }}"
        {{- end }}
```

---

## Values Override Hierarchy

Helm merges values from multiple sources, last one wins:

```
chart defaults (values.yaml)
  ← subchart defaults
    ← parent chart values
      ← -f flag (values file)
        ← --set flag (highest priority)
```

```bash
# Override a nested value
helm install my-app ./my-app \
  --set image.tag=v2.0.0 \
  --set ingress.enabled=true \
  --set ingress.host=myapp.example.com
```

---

## Helm Hooks

Hooks let you run Jobs at specific points in the release lifecycle:

```yaml
annotations:
  "helm.sh/hook": pre-upgrade    # run before upgrade
  "helm.sh/hook": post-install   # run after install
  "helm.sh/hook-weight": "5"     # order of execution (lower = first)
  "helm.sh/hook-delete-policy": before-hook-creation
```

Common uses: database migrations before upgrade, cleanup after uninstall.

---

## Best Practices

- **Pin chart versions** — `helm install my-app bitnami/postgresql --version 15.5.0`
- **Never set passwords via `--set`** — they appear in shell history. Use a values file or external secrets.
- **Use `helm upgrade --install`** in CI/CD — idempotent, works on first deploy and every subsequent one.
- **Version your values files** alongside your application code in git.
- **Use `helm diff`** plugin to preview changes before upgrade.
- **Package charts** with `helm package` and push to a chart registry (ECR, GitHub Container Registry, Artifactory).

```bash
# Install the helm-diff plugin
helm plugin install https://github.com/databus23/helm-diff

# Preview what would change
helm diff upgrade my-db bitnami/postgresql -f new-values.yaml
```
