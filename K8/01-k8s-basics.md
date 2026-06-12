# Kubernetes Architecture & Core Concepts

Kubernetes (K8s) is an open-source container orchestration platform. It automates the deployment, scaling, and management of containerized applications across a cluster of machines. Originally built by Google, now maintained by the CNCF.

The short version: you tell Kubernetes *what* you want running (desired state), and it figures out *how* to make it happen — and keeps it that way, even when machines fail.

---

## Why Kubernetes?

Without orchestration, running containers in production means:
- Manually deciding which host to run each container on
- Writing custom scripts to restart crashed containers
- Building your own load balancing between container instances
- Managing rolling deployments yourself
- No standard way to handle configuration or secrets

Kubernetes solves all of these. It is the operating system for your data center.

---

## Cluster Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│                         CONTROL PLANE                           │
│                                                                 │
│  ┌──────────────┐  ┌──────────────┐  ┌──────────────────────┐  │
│  │  API Server  │  │  Scheduler   │  │  Controller Manager  │  │
│  │  (kube-      │  │  (kube-      │  │  (kube-controller-   │  │
│  │  apiserver)  │  │  scheduler)  │  │  manager)            │  │
│  └──────┬───────┘  └──────────────┘  └──────────────────────┘  │
│         │                                                       │
│  ┌──────▼───────┐                                              │
│  │     etcd     │  (distributed key-value store)               │
│  └──────────────┘                                              │
└─────────────────────────────────────────────────────────────────┘
         │
         │ (watches & talks to API server)
         │
┌────────▼──────────────────────────────────────────────────────┐
│                          WORKER NODES                          │
│                                                                │
│  ┌──────────────────────┐   ┌──────────────────────┐          │
│  │       Node 1         │   │       Node 2         │          │
│  │  ┌────────────────┐  │   │  ┌────────────────┐  │          │
│  │  │ Pod  │  Pod    │  │   │  │ Pod  │  Pod    │  │          │
│  │  └────────────────┘  │   │  └────────────────┘  │          │
│  │  kubelet | kube-proxy│   │  kubelet | kube-proxy│          │
│  └──────────────────────┘   └──────────────────────┘          │
└────────────────────────────────────────────────────────────────┘
```

---

## Control Plane Components

### kube-apiserver
The front door. Every kubectl command, every controller, every node — all communicate through the API server. It validates and processes requests, then persists state to etcd. It is the only component that talks to etcd directly.

```bash
# All kubectl commands hit the API server
kubectl get pods           # GET /api/v1/namespaces/default/pods
kubectl apply -f app.yaml  # POST or PUT to the appropriate resource endpoint
```

### etcd
A distributed, strongly-consistent key-value store. It holds the entire state of the cluster — every object, every configuration, every secret. If you lose etcd and have no backup, you lose your cluster.

- Always run etcd on an odd number of nodes (3, 5) for quorum
- Back it up regularly — `etcdctl snapshot save`

### kube-scheduler
Watches for Pods that have no Node assigned, then selects the best Node to run them on. It considers resource requests, node selectors, taints, tolerations, affinity rules, and more.

### kube-controller-manager
Runs a loop of controllers, each watching the cluster state and reconciling it toward the desired state:
- **Node controller** — marks nodes as not-ready when they go offline
- **Deployment controller** — ensures the right number of ReplicaSet pods are running
- **Endpoints controller** — populates the Endpoints objects for Services
- **Job controller** — runs pods to completion for Job objects

---

## Worker Node Components

### kubelet
An agent running on every node. It takes PodSpec definitions from the API server and ensures the described containers are running and healthy. It is not a container — it talks to the container runtime (containerd, CRI-O) via CRI.

### kube-proxy
Maintains network rules on nodes, implementing the Service abstraction. Routes traffic to the right Pod IP using iptables or IPVS rules.

### Container Runtime
The software that actually runs containers — containerd (most common), CRI-O. Docker was deprecated as a runtime in K8s 1.24.

---

## The Kubernetes Object Model

Everything in Kubernetes is an **object** — a persistent entity in the system that represents a desired state. Every object has:

```yaml
apiVersion: apps/v1         # which API group and version
kind: Deployment            # what type of object
metadata:
  name: my-app              # unique name within a namespace
  namespace: default        # logical grouping
  labels:                   # key-value pairs for selection
    app: my-app
    version: v1
spec:                       # DESIRED STATE — what you want
  replicas: 3
status:                     # CURRENT STATE — what actually exists (managed by K8s)
  availableReplicas: 3
```

The `spec` is what you write. The `status` is what Kubernetes writes back. The controllers constantly reconcile `status` toward `spec`.

---

## Namespaces

Namespaces are virtual clusters within a physical cluster. They provide scope for names and a mechanism to divide cluster resources.

```bash
# List namespaces
kubectl get namespaces

# Default namespaces
# default        — where your objects go if you don't specify
# kube-system    — K8s system components (do not touch)
# kube-public    — publicly readable, rarely used
# kube-node-lease— node heartbeat objects

# Create a namespace
kubectl create namespace staging

# Run commands in a specific namespace
kubectl get pods -n staging
kubectl get pods --all-namespaces   # or -A

# Set default namespace for your current context
kubectl config set-context --current --namespace=staging
```

---

## Labels and Selectors

Labels are the glue that holds Kubernetes together. Services find Pods via labels. Deployments manage ReplicaSets via labels. Node scheduling uses labels.

```yaml
metadata:
  labels:
    app: nginx
    env: production
    version: "1.27"
```

```bash
# Select by label
kubectl get pods -l app=nginx
kubectl get pods -l app=nginx,env=production
kubectl get pods -l 'env in (staging, production)'

# Add a label to a running pod (not recommended in prod — use manifests)
kubectl label pod my-pod tier=frontend
```

---

## Essential kubectl Commands

```bash
# Cluster info
kubectl cluster-info
kubectl get nodes
kubectl get nodes -o wide        # shows IPs, OS, container runtime

# Viewing resources
kubectl get pods
kubectl get pods -o wide         # more detail
kubectl get pods -o yaml         # full YAML output
kubectl get all                  # pods, services, deployments, replicasets

# Inspecting a resource
kubectl describe pod my-pod      # human-readable detail + events
kubectl describe node my-node

# Logs
kubectl logs my-pod
kubectl logs my-pod -c my-container   # if multiple containers in pod
kubectl logs -f my-pod           # follow / tail
kubectl logs --previous my-pod   # logs from crashed previous container

# Exec into a container
kubectl exec -it my-pod -- /bin/sh
kubectl exec -it my-pod -c my-container -- bash

# Port forwarding for local access
kubectl port-forward pod/my-pod 8080:80
kubectl port-forward svc/my-service 8080:80

# Apply / delete
kubectl apply -f manifest.yaml
kubectl apply -f ./manifests/          # apply entire directory
kubectl delete -f manifest.yaml
kubectl delete pod my-pod

# Dry run (see what would happen without applying)
kubectl apply -f manifest.yaml --dry-run=client
kubectl apply -f manifest.yaml --dry-run=server   # also validates against the API

# Diff (what would change vs current state)
kubectl diff -f manifest.yaml
```

---

## Contexts and kubeconfig

kubectl reads `~/.kube/config` to know which cluster to talk to.

```bash
# See all contexts (cluster + user + namespace combinations)
kubectl config get-contexts

# Switch cluster
kubectl config use-context my-cluster

# See current context
kubectl config current-context

# Merge multiple kubeconfigs
KUBECONFIG=~/.kube/config:~/Downloads/new-cluster.yaml kubectl config view --merge --flatten > ~/.kube/config
```

---

## Key Concepts Cheat Sheet

| Concept | What it is |
|---------|------------|
| **Node** | A physical or virtual machine in the cluster |
| **Pod** | The smallest deployable unit — one or more containers |
| **Deployment** | Manages rolling updates of a ReplicaSet |
| **ReplicaSet** | Ensures N copies of a Pod are running |
| **Service** | A stable network endpoint for a set of Pods |
| **Ingress** | HTTP/HTTPS routing from outside the cluster |
| **ConfigMap** | Non-sensitive configuration data |
| **Secret** | Sensitive data (passwords, tokens, keys) |
| **PVC** | A request for persistent storage |
| **Namespace** | A virtual cluster for resource isolation |

---

## Further Reading

- [Kubernetes Concepts Documentation](https://kubernetes.io/docs/concepts/)
- [kubectl Cheat Sheet](https://kubernetes.io/docs/reference/kubectl/cheatsheet/)
- [Kubernetes the Hard Way](https://github.com/kelseyhightower/kubernetes-the-hard-way) — build a cluster from scratch to understand every piece
