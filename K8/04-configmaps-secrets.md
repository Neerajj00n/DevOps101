# ConfigMaps & Secrets

Hard-coded configuration is the enemy of portable applications. Kubernetes provides two objects for injecting configuration into Pods: ConfigMaps for non-sensitive data and Secrets for sensitive data like passwords and tokens.

---

## The Twelve-Factor App Principle

Configuration that changes between environments (dev, staging, prod) should never be baked into the container image. The same image should run in all environments — only the configuration changes.

```
Bad:  image with DB_HOST=localhost baked in
Good: image reads DB_HOST from environment variable, injected by K8s
```

---

## ConfigMaps

ConfigMaps store non-sensitive key-value pairs.

### Creating ConfigMaps

```bash
# From literal values
kubectl create configmap app-config \
  --from-literal=LOG_LEVEL=info \
  --from-literal=APP_PORT=8080

# From a file
kubectl create configmap nginx-config --from-file=nginx.conf

# From a directory (each file becomes a key)
kubectl create configmap app-configs --from-file=./config/

# From a YAML manifest (preferred for GitOps)
kubectl apply -f configmap.yaml
```

### ConfigMap Manifest

```yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: app-config
  namespace: default
data:
  LOG_LEVEL: "info"
  APP_PORT: "8080"
  DATABASE_HOST: "postgres-svc"
  DATABASE_NAME: "myapp"
  config.yaml: |
    server:
      port: 8080
    logging:
      level: info
      format: json
```

### Using ConfigMaps — Environment Variables

```yaml
spec:
  containers:
  - name: app
    image: myapp:v1
    # Inject specific keys as env vars
    env:
    - name: LOG_LEVEL
      valueFrom:
        configMapKeyRef:
          name: app-config
          key: LOG_LEVEL
    - name: APP_PORT
      valueFrom:
        configMapKeyRef:
          name: app-config
          key: APP_PORT
    # Or inject ALL keys as env vars
    envFrom:
    - configMapRef:
        name: app-config
```

### Using ConfigMaps — Volume Mounts

Mount ConfigMap data as files. Useful for config files like nginx.conf or application.yaml.

```yaml
spec:
  volumes:
  - name: config-vol
    configMap:
      name: app-config
  containers:
  - name: app
    image: myapp:v1
    volumeMounts:
    - name: config-vol
      mountPath: /etc/app/config    # each key becomes a file here
      readOnly: true
```

Each key in the ConfigMap becomes a file:
```
/etc/app/config/LOG_LEVEL       → contains "info"
/etc/app/config/config.yaml     → contains the multi-line YAML
```

Mount only a specific key:
```yaml
volumes:
- name: config-vol
  configMap:
    name: app-config
    items:
    - key: config.yaml
      path: app.yaml    # the filename in the mountPath
```

---

## Secrets

Secrets store sensitive data. They are base64-encoded (not encrypted by default in etcd, though encryption at rest can be enabled).

### Secret Types

| Type | Use |
|------|-----|
| `Opaque` | Arbitrary user-defined data (default) |
| `kubernetes.io/dockerconfigjson` | Docker registry credentials |
| `kubernetes.io/tls` | TLS certificate and key |
| `kubernetes.io/service-account-token` | Service account tokens |

### Creating Secrets

```bash
# From literal values (base64 encoded automatically)
kubectl create secret generic db-credentials \
  --from-literal=username=admin \
  --from-literal=password='S3cur3P@ssw0rd!'

# From files
kubectl create secret generic tls-cert \
  --from-file=tls.crt=./server.crt \
  --from-file=tls.key=./server.key

# Docker registry credentials
kubectl create secret docker-registry regcred \
  --docker-server=123456789.dkr.ecr.ap-south-1.amazonaws.com \
  --docker-username=AWS \
  --docker-password=$(aws ecr get-login-password)
```

### Secret Manifest

Values must be base64 encoded manually in manifests:

```bash
echo -n 'admin' | base64          # → YWRtaW4=
echo -n 'S3cur3P@ssw0rd!' | base64  # → UzNjdXIzUEBzc3cwcmQh
```

```yaml
apiVersion: v1
kind: Secret
metadata:
  name: db-credentials
type: Opaque
data:
  username: YWRtaW4=              # base64('admin')
  password: UzNjdXIzUEBzc3cwcmQh  # base64('S3cur3P@ssw0rd!')
```

Or use `stringData` to avoid manual base64 encoding (Kubernetes does it for you):

```yaml
apiVersion: v1
kind: Secret
metadata:
  name: db-credentials
type: Opaque
stringData:
  username: admin
  password: "S3cur3P@ssw0rd!"
```

**Note:** Never commit Secrets with real values to git. Use a secrets manager (AWS Secrets Manager, HashiCorp Vault) and sync them in via the External Secrets Operator or similar tooling.

### Using Secrets — Environment Variables

```yaml
spec:
  containers:
  - name: app
    image: myapp:v1
    env:
    - name: DB_USERNAME
      valueFrom:
        secretKeyRef:
          name: db-credentials
          key: username
    - name: DB_PASSWORD
      valueFrom:
        secretKeyRef:
          name: db-credentials
          key: password
```

### Using Secrets — Volume Mounts

Secrets as files are more secure than env vars — they aren't visible in `kubectl describe pod` and can be updated without restarting the pod.

```yaml
spec:
  volumes:
  - name: secrets-vol
    secret:
      secretName: db-credentials
      defaultMode: 0400    # file permissions
  containers:
  - name: app
    image: myapp:v1
    volumeMounts:
    - name: secrets-vol
      mountPath: /run/secrets
      readOnly: true
```

Files created:
```
/run/secrets/username  → contains "admin"
/run/secrets/password  → contains "S3cur3P@ssw0rd!"
```

### Using Secrets — Image Pull Secrets

```yaml
spec:
  imagePullSecrets:
  - name: regcred      # the docker-registry secret
  containers:
  - name: app
    image: 123456789.dkr.ecr.ap-south-1.amazonaws.com/myapp:v1
```

---

## Immutable ConfigMaps and Secrets

Mark them immutable to prevent accidental updates and improve performance (kubelet stops watching them):

```yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: app-config-v2
immutable: true
data:
  LOG_LEVEL: "info"
```

Use versioned names (`app-config-v1`, `app-config-v2`) for immutable configs, and update the deployment to reference the new version.

---

## Dynamic Updates

ConfigMaps and Secrets mounted as volumes are automatically updated when you change them — no pod restart needed. The update takes about a minute (kubelet sync period).

Environment variables injected via `env`/`envFrom` are **NOT** updated automatically. The Pod must restart.

```bash
# Update a ConfigMap
kubectl edit configmap app-config
# or
kubectl apply -f updated-configmap.yaml

# Force restart pods to pick up env var changes
kubectl rollout restart deployment my-app
```

---

## Best Practices

**ConfigMaps:**
- Store configuration that belongs to the app, not infrastructure secrets
- Use volume mounts for large config files, env vars for simple values
- Version your ConfigMaps if using immutable mode

**Secrets:**
- Enable encryption at rest: `EncryptionConfiguration` API
- Use RBAC to restrict who can read secrets
- Consider the External Secrets Operator to sync from AWS Secrets Manager / Vault
- Avoid `envFrom` for secrets — it injects everything, including things you may add later
- Never log environment variables — your secrets will appear in log aggregators

```bash
# Decode a secret to verify its value
kubectl get secret db-credentials -o jsonpath='{.data.password}' | base64 -d
```
