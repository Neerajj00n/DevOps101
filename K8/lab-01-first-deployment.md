# Lab 01 — Your First Kubernetes Deployment

In this lab you will deploy a real application to Kubernetes, scale it, update it, and roll it back. By the end, you'll have a solid workflow for managing stateless applications in a cluster.

**Time:** ~45 minutes  
**Difficulty:** Beginner

---

## Prerequisites

- minikube installed and running
- kubectl configured to talk to your minikube cluster

---

## Part 1 — Start Your Cluster

```bash
# Start minikube with sufficient resources
minikube start --cpus=2 --memory=2048

# Verify the cluster is running
kubectl cluster-info
kubectl get nodes

# Expected output:
# NAME       STATUS   ROLES           AGE   VERSION
# minikube   Ready    control-plane   1m    v1.30.x
```

---

## Part 2 — Your First Pod

Before using Deployments, create a bare Pod to understand the basics.

```bash
# Create a pod imperatively
kubectl run nginx-test --image=nginx:1.27-alpine --port=80

# Watch the pod come up
kubectl get pods --watch
# Ctrl+C when it shows Running

# Inspect it
kubectl describe pod nginx-test

# Access it locally via port forwarding
kubectl port-forward pod/nginx-test 8080:80 &
curl http://localhost:8080
# You should see the nginx welcome page

# Kill the port-forward
kill %1

# Delete the pod
kubectl delete pod nginx-test
# Note: it's gone. No replacement. That's why we use Deployments.
```

---

## Part 3 — Create a Deployment

Create a file `deployment.yaml`:

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: web-app
  labels:
    app: web-app
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
      containers:
      - name: nginx
        image: nginx:1.27-alpine
        ports:
        - containerPort: 80
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
          initialDelaySeconds: 3
          periodSeconds: 5
        livenessProbe:
          httpGet:
            path: /
            port: 80
          initialDelaySeconds: 10
          periodSeconds: 20
```

```bash
# Apply the deployment
kubectl apply -f deployment.yaml

# Watch the pods being created
kubectl get pods -w
# Ctrl+C when both pods show Running

# Examine the deployment and its pods
kubectl get deployment web-app
kubectl describe deployment web-app

# See the ReplicaSet it created
kubectl get replicaset
```

---

## Part 4 — Explore Self-Healing

Kubernetes automatically replaces failed pods.

```bash
# Get the name of one of the pods
kubectl get pods

# Delete one pod (replace <pod-name> with an actual pod name)
kubectl delete pod <pod-name>

# Immediately watch what happens
kubectl get pods -w
# A new pod starts automatically — the ReplicaSet noticed 1 pod was missing

# Try deleting both pods at once
kubectl delete pod -l app=web-app
# Watch both get recreated
kubectl get pods -w
```

---

## Part 5 — Scaling

```bash
# Scale up to 4 replicas
kubectl scale deployment web-app --replicas=4
kubectl get pods   # now 4 pods

# Scale back to 2
kubectl scale deployment web-app --replicas=2
kubectl get pods   # back to 2 pods

# Or edit the manifest and apply
# Edit deployment.yaml: replicas: 3
kubectl apply -f deployment.yaml
kubectl get pods   # 3 pods
```

---

## Part 6 — Rolling Update

Update the application without downtime.

```bash
# Check current image
kubectl describe deployment web-app | grep Image

# Update the image
kubectl set image deployment/web-app nginx=nginx:1.28-alpine

# Watch the rollout happen
kubectl rollout status deployment/web-app

# Watch pods cycling (old pods terminate, new ones start)
kubectl get pods -w
# Ctrl+C

# Verify the new image
kubectl describe deployment web-app | grep Image
# Should show nginx:1.28-alpine
```

How it works: with `maxSurge: 1` and `maxUnavailable: 0`, Kubernetes creates one new pod with the new image, waits for it to be ready, then terminates one old pod — repeating until all pods are replaced.

---

## Part 7 — Rollback

```bash
# View rollout history
kubectl rollout history deployment/web-app

# Undo the last update (roll back to nginx:1.27-alpine)
kubectl rollout undo deployment/web-app

# Watch the rollback
kubectl rollout status deployment/web-app

# Verify
kubectl describe deployment web-app | grep Image
# Should show nginx:1.27-alpine

# View history with change causes (add --record to your apply command in future)
kubectl rollout history deployment/web-app

# Roll back to a specific revision
kubectl rollout undo deployment/web-app --to-revision=1
```

---

## Part 8 — Expose the Deployment

```bash
# Create a Service to expose the Deployment
kubectl expose deployment web-app --port=80 --type=NodePort

# Get the URL on minikube
minikube service web-app --url
# Copy the URL and open in browser, or:
curl $(minikube service web-app --url)
```

---

## Part 9 — Clean Up

```bash
kubectl delete deployment web-app
kubectl delete service web-app
# or
kubectl delete -f deployment.yaml
```

---

## Summary

| What you did | Command used |
|---|---|
| Created a pod manually | `kubectl run` |
| Applied a Deployment | `kubectl apply -f` |
| Observed self-healing | `kubectl delete pod` |
| Scaled replicas | `kubectl scale` |
| Updated the image | `kubectl set image` |
| Watched a rollout | `kubectl rollout status` |
| Rolled back | `kubectl rollout undo` |
| Exposed via NodePort | `kubectl expose` |

---

## Challenges

1. Write a Deployment for the `httpd:2.4-alpine` image. How does it differ from nginx?
2. Set `maxUnavailable: 1` and `maxSurge: 0` in the strategy. How does the rollout behavior change?
3. Configure the Deployment to keep 5 revisions in history (`revisionHistoryLimit: 5`). Roll forward and back multiple times and inspect `kubectl rollout history`.
