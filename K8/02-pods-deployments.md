# Pods, Deployments & Workloads

Pods are the atomic unit of Kubernetes. Everything else — Deployments, StatefulSets, DaemonSets — is a higher-level abstraction built on top of Pods. Understanding Pods deeply is what makes the rest of Kubernetes click.

---

## Pods

A Pod is one or more containers that share:
- A network namespace (same IP address and port space)
- A storage namespace (can mount the same volumes)
- A lifecycle (they are scheduled together on the same node)

```
┌────────────────────────────────────────┐
│                  Pod                   │
│                                        │
│  ┌─────────────┐  ┌─────────────────┐  │
│  │  Container  │  │  Sidecar        │  │
│  │  (app)      │  │  (log shipper)  │  │
│  └─────────────┘  └─────────────────┘  │
│                                        │
│  Shared: localhost, volumes            │
└────────────────────────────────────────┘
         Node IP: 10.0.1.5
         Pod IP:  172.17.0.4
```

### Why not just run containers?

Kubernetes schedules Pods, not containers. The Pod abstraction handles:
- Init containers that run before the main container
- Sidecar containers for cross-cutting concerns (logging, proxying)
- Shared localhost communication between co-located containers

### Minimal Pod manifest

```yaml
apiVersion: v1
kind: Pod
metadata:
  name: nginx-pod
  labels:
    app: nginx
spec:
  containers:
  - name: nginx
    image: nginx:1.27-alpine
    ports:
    - containerPort: 80
    resources:
      requests:
        memory: "64Mi"
        cpu: "250m"
      limits:
        memory: "128Mi"
        cpu: "500m"
```

```bash
kubectl apply -f pod.yaml
kubectl get pods
kubectl describe pod nginx-pod
kubectl delete pod nginx-pod
```

**Important:** Bare Pods are not self-healing. If the node dies, the Pod is gone. Always use a controller (Deployment, StatefulSet) in production.

---

## Resource Requests and Limits

Resources in Kubernetes are expressed in two dimensions:

| | Meaning |
|--|---------|
| `requests` | What the scheduler uses to find a node. The pod is *guaranteed* this amount. |
| `limits` | The hard ceiling. Exceed CPU → throttled. Exceed memory → OOMKilled. |

```yaml
resources:
  requests:
    memory: "128Mi"
    cpu: "100m"     # 100 millicores = 0.1 CPU core
  limits:
    memory: "256Mi"
    cpu: "500m"
```

CPU is compressible — excess usage is throttled. Memory is not — exceeding the limit kills the container.

**Best practice:** always set both. A pod without limits can starve other pods on the same node.

---

## Pod Lifecycle

```
Pending → Running → Succeeded
                 ↘ Failed
                 ↘ Unknown
```

| Phase | Meaning |
|-------|---------|
| `Pending` | Accepted by cluster, not yet scheduled or image not pulled |
| `Running` | At least one container is running |
| `Succeeded` | All containers exited with code 0 (Jobs) |
| `Failed` | At least one container exited with non-zero code |
| `Unknown` | Node communication lost |

### Container States

```bash
kubectl describe pod my-pod    # look at "Containers:" section
```

| State | Meaning |
|-------|---------|
| `Waiting` | Not running yet — pulling image, waiting for secret |
| `Running` | Process is running |
| `Terminated` | Process ended, code stored in `exitCode` |

---

## Init Containers

Run to completion *before* the main containers start. Useful for:
- Waiting for a database to be ready
- Pulling secrets from a vault
- Running database migrations

```yaml
spec:
  initContainers:
  - name: wait-for-db
    image: busybox
    command: ['sh', '-c', 'until nc -z postgres-svc 5432; do sleep 2; done']
  containers:
  - name: app
    image: myapp:v1
```

---

## ReplicaSets

A ReplicaSet ensures a specified number of Pod replicas are running at any time. If a Pod dies, the ReplicaSet creates a new one.

```yaml
apiVersion: apps/v1
kind: ReplicaSet
metadata:
  name: nginx-rs
spec:
  replicas: 3
  selector:
    matchLabels:
      app: nginx
  template:                # Pod template — same as a Pod spec
    metadata:
      labels:
        app: nginx
    spec:
      containers:
      - name: nginx
        image: nginx:1.27-alpine
```

**You almost never write ReplicaSets directly.** Deployments manage them for you — and give you rollout history.

---

## Deployments

A Deployment manages a ReplicaSet, giving you:
- **Declarative updates** — change the image, Kubernetes handles the rollout
- **Rollback** — revert to a previous version instantly
- **Rolling updates** — zero-downtime by default
- **Scaling** — change `replicas` and apply

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: nginx-deployment
  labels:
    app: nginx
spec:
  replicas: 3
  selector:
    matchLabels:
      app: nginx
  strategy:
    type: RollingUpdate
    rollingUpdate:
      maxSurge: 1         # how many extra pods can be created above desired
      maxUnavailable: 0   # how many pods can be unavailable during update
  template:
    metadata:
      labels:
        app: nginx
    spec:
      containers:
      - name: nginx
        image: nginx:1.27-alpine
        ports:
        - containerPort: 80
        readinessProbe:
          httpGet:
            path: /
            port: 80
          initialDelaySeconds: 5
          periodSeconds: 5
        livenessProbe:
          httpGet:
            path: /
            port: 80
          initialDelaySeconds: 15
          periodSeconds: 20
```

### Deployment Commands

```bash
# Apply
kubectl apply -f deployment.yaml

# Scale
kubectl scale deployment nginx-deployment --replicas=5

# Update image (imperative — use apply in production)
kubectl set image deployment/nginx-deployment nginx=nginx:1.28-alpine

# Rollout status
kubectl rollout status deployment/nginx-deployment

# Rollout history
kubectl rollout history deployment/nginx-deployment

# Rollback to previous version
kubectl rollout undo deployment/nginx-deployment

# Rollback to a specific revision
kubectl rollout undo deployment/nginx-deployment --to-revision=2

# Pause / resume a rollout
kubectl rollout pause deployment/nginx-deployment
kubectl rollout resume deployment/nginx-deployment
```

---

## Health Probes

Without health probes, Kubernetes doesn't know if your app is actually ready. A container that is running but returning 500s looks fine to Kubernetes — unless you tell it to check.

### Liveness Probe
Restarts the container if it fails. Use for detecting deadlocks.

### Readiness Probe
Removes the Pod from Service load balancing if it fails. Use for detecting when the app is not ready to serve traffic (startup, overload).

### Startup Probe
Gives slow-starting apps time to initialize before liveness kicks in.

```yaml
livenessProbe:
  httpGet:
    path: /healthz
    port: 8080
  initialDelaySeconds: 15
  periodSeconds: 20
  failureThreshold: 3

readinessProbe:
  httpGet:
    path: /ready
    port: 8080
  initialDelaySeconds: 5
  periodSeconds: 5

startupProbe:
  httpGet:
    path: /healthz
    port: 8080
  failureThreshold: 30   # allows 30 * 10s = 5 minutes to start
  periodSeconds: 10
```

Probes can use:
- `httpGet` — HTTP GET, success if 200-399
- `tcpSocket` — TCP connection, success if port is open
- `exec` — runs a command, success if exit code is 0

---

## StatefulSets

For stateful applications that need:
- Stable, persistent hostnames (`pod-0`, `pod-1`, `pod-2`)
- Ordered startup and termination
- Stable storage per pod

```yaml
apiVersion: apps/v1
kind: StatefulSet
metadata:
  name: postgres
spec:
  serviceName: "postgres"
  replicas: 1
  selector:
    matchLabels:
      app: postgres
  template:
    metadata:
      labels:
        app: postgres
    spec:
      containers:
      - name: postgres
        image: postgres:16-alpine
        env:
        - name: POSTGRES_PASSWORD
          valueFrom:
            secretKeyRef:
              name: postgres-secret
              key: password
        volumeMounts:
        - name: data
          mountPath: /var/lib/postgresql/data
  volumeClaimTemplates:             # each pod gets its own PVC
  - metadata:
      name: data
    spec:
      accessModes: ["ReadWriteOnce"]
      resources:
        requests:
          storage: 10Gi
```

---

## DaemonSets

Runs exactly one Pod on every node (or a subset via nodeSelector). Use cases:
- Log collectors (Fluentd, Filebeat)
- Monitoring agents (Prometheus node-exporter)
- Network plugins (Cilium, Calico agents)

```yaml
apiVersion: apps/v1
kind: DaemonSet
metadata:
  name: fluentd
spec:
  selector:
    matchLabels:
      app: fluentd
  template:
    metadata:
      labels:
        app: fluentd
    spec:
      containers:
      - name: fluentd
        image: fluent/fluentd:v1.16
```

---

## Jobs and CronJobs

### Job — run to completion

```yaml
apiVersion: batch/v1
kind: Job
metadata:
  name: db-migration
spec:
  template:
    spec:
      containers:
      - name: migrate
        image: myapp:v1
        command: ["./migrate.sh"]
      restartPolicy: OnFailure   # required for Jobs
  backoffLimit: 3   # retry 3 times on failure
```

### CronJob — scheduled job

```yaml
apiVersion: batch/v1
kind: CronJob
metadata:
  name: db-backup
spec:
  schedule: "0 2 * * *"   # every day at 2am (cron syntax)
  jobTemplate:
    spec:
      template:
        spec:
          containers:
          - name: backup
            image: postgres:16-alpine
            command: ["pg_dump", "-h", "postgres-svc", "mydb"]
          restartPolicy: OnFailure
```

---

## Horizontal Pod Autoscaler (HPA)

Automatically scales Deployments based on CPU, memory, or custom metrics.

```yaml
apiVersion: autoscaling/v2
kind: HorizontalPodAutoscaler
metadata:
  name: nginx-hpa
spec:
  scaleTargetRef:
    apiVersion: apps/v1
    kind: Deployment
    name: nginx-deployment
  minReplicas: 2
  maxReplicas: 10
  metrics:
  - type: Resource
    resource:
      name: cpu
      target:
        type: Utilization
        averageUtilization: 70
```

```bash
kubectl get hpa
kubectl describe hpa nginx-hpa
```

**Prerequisite:** Metrics Server must be installed in the cluster.

---

## Workload Summary

| Controller | Use case |
|-----------|----------|
| **Pod** | Dev/testing only. No self-healing. |
| **Deployment** | Stateless apps. Rolling updates. 95% of use cases. |
| **StatefulSet** | Databases, queues. Stable identity + storage. |
| **DaemonSet** | Per-node agents. Logging, monitoring, networking. |
| **Job** | One-time tasks. Migrations, batch processing. |
| **CronJob** | Scheduled recurring tasks. |
