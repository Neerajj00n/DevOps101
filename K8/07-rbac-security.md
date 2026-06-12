# RBAC & Security

Kubernetes has broad attack surface by default. Out-of-the-box, any pod in the cluster can reach the API server, and workloads often run as root. Securing a cluster is about applying the principle of least privilege at every layer: what can talk to the API, what pods can do, what network traffic is allowed, and what images can run.

---

## Authentication vs Authorization

```
Request → Authentication → Authorization (RBAC) → Admission Control → API Server
           (who are you?)   (what can you do?)      (is this valid?)
```

- **Authentication** — Kubernetes doesn't manage users directly. It trusts certificates, tokens, and OIDC providers (like AWS IAM for EKS).
- **Authorization** — RBAC controls what authenticated users/services can do.
- **Admission Control** — Webhooks that can mutate or validate requests before they're persisted.

---

## RBAC Core Concepts

Four objects power RBAC:

| Object | Scope | What it does |
|--------|-------|--------------|
| `Role` | Namespace | Defines permissions within a namespace |
| `ClusterRole` | Cluster-wide | Defines permissions across all namespaces or for cluster resources |
| `RoleBinding` | Namespace | Grants a Role to a user/group/serviceaccount within a namespace |
| `ClusterRoleBinding` | Cluster-wide | Grants a ClusterRole to a user/group/serviceaccount cluster-wide |

**RBAC is additive — there are no deny rules.** If a permission isn't explicitly granted, it is denied.

---

## Service Accounts

Pods authenticate to the API server using Service Accounts. Every namespace has a `default` service account, but you should create dedicated ones per application.

```yaml
apiVersion: v1
kind: ServiceAccount
metadata:
  name: my-app-sa
  namespace: production
automountServiceAccountToken: false   # disable auto-mounting unless needed
```

Assign a service account to a pod:

```yaml
spec:
  serviceAccountName: my-app-sa
  automountServiceAccountToken: false  # can also set at pod level
  containers:
  - name: app
    image: myapp:v1
```

---

## Roles and ClusterRoles

```yaml
# Role — namespaced
apiVersion: rbac.authorization.k8s.io/v1
kind: Role
metadata:
  name: pod-reader
  namespace: staging
rules:
- apiGroups: [""]                # "" = core API group (pods, services, configmaps)
  resources: ["pods", "pods/log"]
  verbs: ["get", "list", "watch"]
- apiGroups: ["apps"]
  resources: ["deployments"]
  verbs: ["get", "list"]
```

```yaml
# ClusterRole — cluster-wide
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRole
metadata:
  name: node-reader
rules:
- apiGroups: [""]
  resources: ["nodes"]
  verbs: ["get", "list", "watch"]
- apiGroups: ["metrics.k8s.io"]
  resources: ["nodes", "pods"]
  verbs: ["get", "list"]
```

### Common Verbs

| Verb | HTTP Method | Meaning |
|------|-------------|---------|
| `get` | GET | Read a specific resource |
| `list` | GET | List all resources |
| `watch` | GET+watch | Stream changes |
| `create` | POST | Create a resource |
| `update` | PUT | Fully replace a resource |
| `patch` | PATCH | Partially update a resource |
| `delete` | DELETE | Delete a resource |
| `*` | All | All verbs (use sparingly) |

---

## RoleBindings and ClusterRoleBindings

```yaml
# RoleBinding — grants Role to a ServiceAccount within a namespace
apiVersion: rbac.authorization.k8s.io/v1
kind: RoleBinding
metadata:
  name: my-app-pod-reader
  namespace: staging
subjects:
- kind: ServiceAccount
  name: my-app-sa
  namespace: staging
- kind: User                      # external user (cert or OIDC)
  name: alice@example.com
  apiGroup: rbac.authorization.k8s.io
- kind: Group
  name: developers
  apiGroup: rbac.authorization.k8s.io
roleRef:
  kind: Role
  name: pod-reader
  apiGroup: rbac.authorization.k8s.io
```

```yaml
# ClusterRoleBinding — grants ClusterRole cluster-wide
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding
metadata:
  name: ci-deployer
subjects:
- kind: ServiceAccount
  name: ci-sa
  namespace: ci
roleRef:
  kind: ClusterRole
  name: deployment-manager
  apiGroup: rbac.authorization.k8s.io
```

**Tip:** You can use a `RoleBinding` to bind a `ClusterRole` in a single namespace. This lets you define roles once and reuse them across namespaces.

---

## Checking Permissions

```bash
# Can I do this?
kubectl auth can-i create deployments
kubectl auth can-i delete pods --namespace production

# Can another user/sa do this?
kubectl auth can-i get secrets \
  --as=system:serviceaccount:production:my-app-sa \
  --namespace production

# List all permissions for the current user
kubectl auth can-i --list
kubectl auth can-i --list --namespace staging

# Who can do what to pods?
kubectl who-can get pods    # requires 'kubectl-who-can' plugin
```

---

## Pod Security

### Security Context

Define security settings at the Pod or Container level:

```yaml
spec:
  securityContext:
    runAsNonRoot: true       # fail if image runs as root
    runAsUser: 1000          # UID to run as
    runAsGroup: 3000
    fsGroup: 2000            # GID for volume ownership
    seccompProfile:
      type: RuntimeDefault   # enable default seccomp profile

  containers:
  - name: app
    image: myapp:v1
    securityContext:
      allowPrivilegeEscalation: false  # cannot gain more privileges than parent
      readOnlyRootFilesystem: true     # container can't write to its own FS
      capabilities:
        drop:
        - ALL                # drop all Linux capabilities
        add:
        - NET_BIND_SERVICE   # only add back what's needed (bind to port < 1024)
```

### Pod Security Standards (PSS)

Kubernetes 1.23+ enforces security standards at the namespace level via labels (replaced the deprecated PodSecurityPolicies):

```bash
# Apply a security standard to a namespace
kubectl label namespace production \
  pod-security.kubernetes.io/enforce=restricted \
  pod-security.kubernetes.io/warn=restricted

# Three levels:
# privileged  — no restrictions (avoid in production)
# baseline    — minimal restrictions (prevents known privilege escalations)
# restricted  — heavily restricted (best practice for most workloads)
```

---

## Secrets Security

By default, Secrets are only base64-encoded in etcd — not encrypted. Enable encryption:

```yaml
# /etc/kubernetes/manifests/kube-apiserver.yaml
# Add: --encryption-provider-config=/etc/kubernetes/encryption-config.yaml
```

```yaml
# /etc/kubernetes/encryption-config.yaml
apiVersion: apiserver.config.k8s.io/v1
kind: EncryptionConfiguration
resources:
- resources:
  - secrets
  providers:
  - aescbc:
      keys:
      - name: key1
        secret: <base64-encoded-32-byte-key>
  - identity: {}   # fallback for existing unencrypted secrets
```

**Production pattern:** Don't store real secrets in Kubernetes Secrets at all. Use:
- AWS Secrets Manager + External Secrets Operator
- HashiCorp Vault + Vault Agent Injector
- AWS Systems Manager Parameter Store + External Secrets Operator

---

## Network Policies for Security

```yaml
# Default deny all — start from zero trust
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: default-deny-all
  namespace: production
spec:
  podSelector: {}
  policyTypes:
  - Ingress
  - Egress
---
# Allow app to reach its database only
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: app-to-db
  namespace: production
spec:
  podSelector:
    matchLabels:
      app: postgres
  policyTypes:
  - Ingress
  ingress:
  - from:
    - podSelector:
        matchLabels:
          app: myapp
    ports:
    - port: 5432
```

---

## Image Security

```bash
# Scan images for vulnerabilities before deploying
docker scout cves myapp:v1
trivy image myapp:v1

# Use image digest (immutable) instead of tag
image: nginx@sha256:abc123...

# Enforce image signing in production (Cosign + Sigstore)
cosign sign myapp:v1
```

Admission controllers like **Kyverno** or **OPA/Gatekeeper** can enforce policies:
- Require specific labels on all deployments
- Deny images from untrusted registries
- Require resource limits on all pods
- Deny containers running as root

---

## Auditing

```bash
# View audit logs (if enabled on the cluster)
# Audit policy is configured in kube-apiserver

# Check what happened to a resource
kubectl get events --sort-by='.lastTimestamp'
kubectl get events -n production

# For EKS, CloudTrail captures all API server calls
aws cloudtrail lookup-events --lookup-attributes AttributeKey=ResourceName,AttributeValue=my-pod
```

---

## Security Checklist

| Area | Check |
|------|-------|
| RBAC | No wildcard `*` permissions in production |
| RBAC | Each app uses its own ServiceAccount |
| RBAC | `cluster-admin` not given to any user/SA routinely |
| Pods | `runAsNonRoot: true` on all pods |
| Pods | `readOnlyRootFilesystem: true` where possible |
| Pods | `allowPrivilegeEscalation: false` |
| Pods | All capabilities dropped, only needed ones added back |
| Pods | Resource limits set on all containers |
| Network | Default-deny NetworkPolicy per namespace |
| Secrets | Encryption at rest enabled |
| Secrets | Using external secrets manager in production |
| Images | Images scanned for CVEs in CI pipeline |
| Images | No `latest` tags in production |
| Namespaces | Pod Security Standards applied |
