# Lab 03 — Deploying a Stateful Application

In this lab you will deploy a complete stateful application stack: a PostgreSQL database with persistent storage, a web application that reads from the database, and all configuration handled via ConfigMaps and Secrets. You will also test failure scenarios to see how Kubernetes recovers stateful workloads.

**Time:** ~75 minutes  
**Difficulty:** Intermediate-Advanced

---

## Prerequisites

- minikube running with ingress addon enabled (from Labs 01 and 02)
- kubectl configured
- Completed Labs 01 and 02

---

## Architecture

```
                  Ingress
                     |
                     v
               frontend-svc (ClusterIP)
                     |
                     v
             [Frontend Deployment]
               nginx + static app
                     |
                     v (via env vars)
               backend-svc (ClusterIP)
                     |
                     v
            [Backend Deployment]
             reads from database
                     |
                     v
               postgres-svc (ClusterIP, Headless)
                     |
                     v
           [PostgreSQL StatefulSet]
                     |
                     v
            PersistentVolumeClaim (10Gi)
```

---

## Part 1 — Create a Namespace

Keep all resources organized in a dedicated namespace.

```bash
kubectl create namespace myapp

# Set it as the default namespace for this lab
kubectl config set-context --current --namespace=myapp

# Verify
kubectl config view --minify | grep namespace
```

---

## Part 2 — Create Secrets and ConfigMaps

Create `config.yaml`:

```yaml
apiVersion: v1
kind: Secret
metadata:
  name: postgres-secret
  namespace: myapp
type: Opaque
stringData:
  POSTGRES_PASSWORD: "supersecretpassword"
  POSTGRES_USER: "appuser"
  POSTGRES_DB: "myapp"
---
apiVersion: v1
kind: ConfigMap
metadata:
  name: app-config
  namespace: myapp
data:
  APP_ENV: "production"
  LOG_LEVEL: "info"
  DB_HOST: "postgres-svc"
  DB_PORT: "5432"
  DB_NAME: "myapp"
```

```bash
kubectl apply -f config.yaml

# Verify secrets and configmaps
kubectl get secrets
kubectl get configmaps

# Inspect (values are base64 encoded in Secrets)
kubectl describe secret postgres-secret
kubectl describe configmap app-config

# Decode a secret value to verify
kubectl get secret postgres-secret -o jsonpath='{.data.POSTGRES_PASSWORD}' | base64 -d
echo  # add newline
```

---

## Part 3 — Deploy PostgreSQL as a StatefulSet

Create `postgres.yaml`:

```yaml
apiVersion: v1
kind: Service
metadata:
  name: postgres-svc
  namespace: myapp
  labels:
    app: postgres
spec:
  clusterIP: None      # Headless service — gives each pod a stable DNS name
  selector:
    app: postgres
  ports:
  - port: 5432
    targetPort: 5432
---
apiVersion: apps/v1
kind: StatefulSet
metadata:
  name: postgres
  namespace: myapp
spec:
  serviceName: "postgres-svc"
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
        ports:
        - containerPort: 5432
        env:
        - name: POSTGRES_PASSWORD
          valueFrom:
            secretKeyRef:
              name: postgres-secret
              key: POSTGRES_PASSWORD
        - name: POSTGRES_USER
          valueFrom:
            secretKeyRef:
              name: postgres-secret
              key: POSTGRES_USER
        - name: POSTGRES_DB
          valueFrom:
            secretKeyRef:
              name: postgres-secret
              key: POSTGRES_DB
        - name: PGDATA
          value: /var/lib/postgresql/data/pgdata
        resources:
          requests:
            memory: "128Mi"
            cpu: "100m"
          limits:
            memory: "256Mi"
            cpu: "500m"
        readinessProbe:
          exec:
            command:
            - pg_isready
            - -U
            - appuser
            - -d
            - myapp
          initialDelaySeconds: 10
          periodSeconds: 5
        livenessProbe:
          exec:
            command:
            - pg_isready
            - -U
            - appuser
          initialDelaySeconds: 30
          periodSeconds: 10
        volumeMounts:
        - name: postgres-data
          mountPath: /var/lib/postgresql/data
  volumeClaimTemplates:
  - metadata:
      name: postgres-data
    spec:
      accessModes: ["ReadWriteOnce"]
      resources:
        requests:
          storage: 1Gi    # small for the lab
```

```bash
kubectl apply -f postgres.yaml

# Watch the StatefulSet pod start up
kubectl get pods -w -n myapp
# Note the pod name: postgres-0 (not a random hash like Deployments!)

# Wait until it shows Ready 1/1
# Then check the PVC was created
kubectl get pvc -n myapp
# NAME                     STATUS   VOLUME          CAPACITY   ACCESS MODES
# postgres-data-postgres-0 Bound    pvc-abc123...   1Gi        RWO
```

---

## Part 4 — Seed the Database

```bash
# Get into the postgres pod
kubectl exec -it postgres-0 -n myapp -- psql -U appuser -d myapp

-- Inside psql:
CREATE TABLE visitors (
  id SERIAL PRIMARY KEY,
  name VARCHAR(100),
  visited_at TIMESTAMP DEFAULT NOW()
);

INSERT INTO visitors (name) VALUES ('Alice'), ('Bob'), ('Charlie');

SELECT * FROM visitors;

\q
```

---

## Part 5 — Test Data Persistence

This is the key test of persistent storage.

```bash
# Delete the postgres pod
kubectl delete pod postgres-0 -n myapp

# Watch it restart automatically (StatefulSet recreates it)
kubectl get pods -n myapp -w
# Wait for postgres-0 to show Running again

# Verify data survived the pod deletion
kubectl exec -it postgres-0 -n myapp -- psql -U appuser -d myapp -c "SELECT * FROM visitors;"
# Data should still be there! The PVC persisted it.
```

---

## Part 6 — Deploy the Application

Create `app.yaml`:

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: web-app
  namespace: myapp
spec:
  replicas: 2
  selector:
    matchLabels:
      app: web-app
  template:
    metadata:
      labels:
        app: web-app
    spec:
      initContainers:
      - name: wait-for-db
        image: busybox:1.36
        command:
        - sh
        - -c
        - |
          until nc -z postgres-svc 5432; do
            echo "Waiting for postgres..."
            sleep 3
          done
          echo "Database is ready!"
      containers:
      - name: app
        image: nginx:1.27-alpine
        ports:
        - containerPort: 80
        envFrom:
        - configMapRef:
            name: app-config
        env:
        - name: DB_USER
          valueFrom:
            secretKeyRef:
              name: postgres-secret
              key: POSTGRES_USER
        - name: DB_PASSWORD
          valueFrom:
            secretKeyRef:
              name: postgres-secret
              key: POSTGRES_PASSWORD
        resources:
          requests:
            memory: "32Mi"
            cpu: "50m"
          limits:
            memory: "64Mi"
            cpu: "100m"
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
---
apiVersion: v1
kind: Service
metadata:
  name: web-svc
  namespace: myapp
spec:
  type: ClusterIP
  selector:
    app: web-app
  ports:
  - port: 80
    targetPort: 80
```

```bash
kubectl apply -f app.yaml

# Watch init container run first, then main container
kubectl get pods -n myapp -w
# pod shows Init:0/1 then PodInitializing then Running

# Verify environment variables are injected
kubectl exec -it -n myapp deploy/web-app -- env | grep -E "APP_ENV|LOG_LEVEL|DB_"
```

---

## Part 7 — Create an Ingress

Create `app-ingress.yaml`:

```yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: app-ingress
  namespace: myapp
spec:
  ingressClassName: nginx
  rules:
  - http:
      paths:
      - path: /
        pathType: Prefix
        backend:
          service:
            name: web-svc
            port:
              number: 80
```

```bash
kubectl apply -f app-ingress.yaml

# Test the app
curl http://$(minikube ip)/
```

---

## Part 8 — Simulate Failure Scenarios

### Scenario A: App pod crashes

```bash
# Delete all app pods
kubectl delete pods -l app=web-app -n myapp

# Watch the Deployment replace them immediately
kubectl get pods -n myapp -w
# New pods start with init container (wait-for-db) again
```

### Scenario B: Simulate database load

```bash
# Connect to postgres and insert more data while app is running
kubectl exec -it postgres-0 -n myapp -- psql -U appuser -d myapp -c \
  "INSERT INTO visitors (name) SELECT 'Load Test ' || generate_series(1, 100);"

kubectl exec -it postgres-0 -n myapp -- psql -U appuser -d myapp -c \
  "SELECT COUNT(*) FROM visitors;"
```

### Scenario C: Scale the app tier (stateless)

```bash
# Scale the web app up (stateless — easy)
kubectl scale deployment web-app --replicas=4 -n myapp
kubectl get pods -n myapp

# The database is the stateful part — it's NOT scaled this simply
# Proper database scaling requires replication (read replicas, clustering)
kubectl scale statefulset postgres --replicas=1 -n myapp  # keep at 1 for this lab
```

---

## Part 9 — Inspect the Full Stack

```bash
# See everything in the namespace
kubectl get all -n myapp

# See storage
kubectl get pvc -n myapp
kubectl get pv

# Check resource consumption
kubectl top pods -n myapp    # requires metrics-server: minikube addons enable metrics-server

# View logs
kubectl logs -l app=web-app -n myapp
kubectl logs postgres-0 -n myapp
```

---

## Part 10 — Clean Up

```bash
# Delete all resources in the namespace
kubectl delete namespace myapp

# The PVCs are also deleted when the namespace is deleted (reclaimPolicy: Delete)
# In production with Retain policy, you would need to manually delete PVs

# Reset default namespace
kubectl config set-context --current --namespace=default
```

---

## Summary

| Concept | What you learned |
|---------|-----------------|
| Namespace | Isolated all resources in one logical group |
| Secrets | Injected sensitive DB credentials without hardcoding |
| ConfigMap | Injected non-sensitive app configuration |
| StatefulSet | Deployed Postgres with a stable pod name (postgres-0) |
| Headless Service | Gave postgres-0 a predictable DNS name |
| PVC | Data survived pod deletion and restart |
| Init Container | App waited for DB to be ready before starting |
| envFrom | Injected all ConfigMap keys as environment variables |

---

## Challenges

1. Enable encryption at rest for Secrets. The command is complex for minikube — research how to configure `EncryptionConfiguration` and implement it.
2. The PostgreSQL StatefulSet currently has 1 replica. Research what would be needed to run a PostgreSQL HA setup (hint: look into bitnami/postgresql Helm chart with replication enabled).
3. Add a `CronJob` that runs `pg_dump` every minute (for testing) and logs the output. Inspect the job pods and logs.
4. Set up resource quotas for the `myapp` namespace to limit total CPU and memory usage across all pods.
