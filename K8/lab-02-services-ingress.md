# Lab 02 — Services and Ingress

In this lab you will deploy a two-tier application (frontend + backend API), connect the tiers using a ClusterIP Service, and expose the frontend to the outside world using an Ingress controller. You'll also practice debugging common networking problems.

**Time:** ~60 minutes  
**Difficulty:** Intermediate

---

## Prerequisites

- minikube running (from Lab 01)
- kubectl configured
- Completed Lab 01 (understand Deployments)

---

## Architecture

```
Browser
   |
   v
Ingress (nginx) - routes by path
   +-- /api/*  --> backend-svc:8080  --> backend Deployment (echo API)
   +-- /*      --> frontend-svc:80   --> frontend Deployment (nginx)
```

---

## Part 1 — Enable Ingress on minikube

```bash
# Enable the nginx ingress controller addon
minikube addons enable ingress

# Wait for it to be ready
kubectl wait --namespace ingress-nginx \
  --for=condition=ready pod \
  --selector=app.kubernetes.io/component=controller \
  --timeout=90s

# Verify
kubectl get pods -n ingress-nginx
```

---

## Part 2 — Deploy the Backend API

Create `backend.yaml`:

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: backend
  labels:
    app: backend
spec:
  replicas: 2
  selector:
    matchLabels:
      app: backend
  template:
    metadata:
      labels:
        app: backend
    spec:
      containers:
      - name: api
        image: hashicorp/http-echo:latest
        args:
        - "-text=Hello from backend!"
        - "-listen=:8080"
        ports:
        - containerPort: 8080
        resources:
          requests:
            memory: "16Mi"
            cpu: "25m"
          limits:
            memory: "32Mi"
            cpu: "50m"
        readinessProbe:
          httpGet:
            path: /
            port: 8080
          initialDelaySeconds: 3
          periodSeconds: 5
---
apiVersion: v1
kind: Service
metadata:
  name: backend-svc
spec:
  type: ClusterIP
  selector:
    app: backend
  ports:
  - port: 8080
    targetPort: 8080
```

```bash
kubectl apply -f backend.yaml
kubectl get pods -l app=backend
kubectl get svc backend-svc
```

---

## Part 3 — Deploy the Frontend

Create `frontend.yaml`:

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: frontend
  labels:
    app: frontend
spec:
  replicas: 2
  selector:
    matchLabels:
      app: frontend
  template:
    metadata:
      labels:
        app: frontend
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
---
apiVersion: v1
kind: Service
metadata:
  name: frontend-svc
spec:
  type: ClusterIP
  selector:
    app: frontend
  ports:
  - port: 80
    targetPort: 80
```

```bash
kubectl apply -f frontend.yaml
kubectl get pods -l app=frontend
kubectl get svc frontend-svc
```

---

## Part 4 — Verify Internal Connectivity

Before creating the Ingress, test that Services work internally.

```bash
# Run a debug pod with networking tools
kubectl run debug --image=nicolaka/netshoot -it --rm -- bash

# Inside the debug pod, test the services:
curl http://frontend-svc:80
# Should return nginx HTML

curl http://backend-svc:8080
# Should return "Hello from backend!"

# Test DNS resolution
nslookup backend-svc
nslookup backend-svc.default.svc.cluster.local

exit
```

---

## Part 5 — Create the Ingress

Create `ingress.yaml`:

```yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: app-ingress
  annotations:
    nginx.ingress.kubernetes.io/rewrite-target: /
spec:
  ingressClassName: nginx
  rules:
  - http:
      paths:
      - path: /api
        pathType: Prefix
        backend:
          service:
            name: backend-svc
            port:
              number: 8080
      - path: /
        pathType: Prefix
        backend:
          service:
            name: frontend-svc
            port:
              number: 80
```

```bash
kubectl apply -f ingress.yaml

# Check the Ingress
kubectl get ingress
kubectl describe ingress app-ingress

# Get minikube's IP
minikube ip
```

---

## Part 6 — Test the Ingress

```bash
MINIKUBE_IP=$(minikube ip)

# Test frontend (served at /)
curl http://$MINIKUBE_IP/
# Should return nginx HTML

# Test backend (served at /api)
curl http://$MINIKUBE_IP/api
# Should return "Hello from backend!"
```

---

## Part 7 — Explore Service Types

```bash
# Change the frontend service to NodePort
kubectl patch svc frontend-svc -p '{"spec":{"type":"NodePort"}}'

# See the assigned NodePort
kubectl get svc frontend-svc
# EXTERNAL-IP is <none>, but NODE-PORT shows the port (e.g. 31234)

# Access directly via NodePort (bypasses Ingress)
NODEPORT=$(kubectl get svc frontend-svc -o jsonpath='{.spec.ports[0].nodePort}')
curl http://$(minikube ip):$NODEPORT

# Restore to ClusterIP
kubectl patch svc frontend-svc -p '{"spec":{"type":"ClusterIP","nodePort":null}}'
```

---

## Part 8 — Debugging Practice

### Break it intentionally

Create `broken-svc.yaml`:

```yaml
apiVersion: v1
kind: Service
metadata:
  name: broken-svc
spec:
  type: ClusterIP
  selector:
    app: doesnotexist
  ports:
  - port: 80
    targetPort: 80
```

```bash
kubectl apply -f broken-svc.yaml
kubectl run debug --image=nicolaka/netshoot -it --rm -- curl http://broken-svc
# This will fail (connection refused or timeout)
```

### Diagnose and fix

```bash
# Step 1: Check if endpoints are populated
kubectl get endpoints broken-svc
# ENDPOINTS = <none>  <- this is the problem

# Step 2: Check what labels exist on the running pods
kubectl get pods --show-labels

# Step 3: Find the mismatch - selector vs actual pod labels
kubectl describe svc broken-svc
# Selector: app=doesnotexist  <- no pods have this label

# Fix: update the selector
kubectl patch svc broken-svc -p '{"spec":{"selector":{"app":"frontend"}}}'

# Verify endpoints are now populated
kubectl get endpoints broken-svc

# Test again
kubectl run debug --image=nicolaka/netshoot -it --rm -- curl http://broken-svc
```

---

## Part 9 — Clean Up

```bash
kubectl delete -f ingress.yaml
kubectl delete -f frontend.yaml
kubectl delete -f backend.yaml
kubectl delete svc broken-svc
```

---

## Summary

| Concept | What you did |
|---------|-------------|
| ClusterIP Service | Connected backend pods to a stable internal name |
| Service discovery | Used DNS names between pods |
| Ingress | Routed external HTTP traffic by path |
| Load balancing | Traffic spread across backend replicas |
| Service debugging | Used endpoints to diagnose broken services |

---

## Challenges

1. Add a third backend service and a new Ingress rule for `/v2` routing to it.
2. Configure the Ingress to route based on hostname instead of path. Use `/etc/hosts` to map a fake domain to the minikube IP.
3. Scale the backend to 5 replicas. Add a loop hitting `/api` and watch the Deployment handle the load.
