# 05 — Kubernetes

> Docker taught you how to package an app. Kubernetes teaches you how to run it at scale — across fleets of machines, with self-healing, rolling updates, and zero-downtime deployments. Every modern cloud-native stack runs on (or alongside) Kubernetes.

---

## What You'll Learn

- What Kubernetes is and why it exists
- The architecture: control plane, nodes, etcd, and the API
- Core objects: Pods, Deployments, Services, ConfigMaps, Secrets
- Networking: how traffic flows in and out of a cluster
- Storage: PersistentVolumes, PersistentVolumeClaims, StorageClasses
- Helm: the package manager for Kubernetes
- RBAC and security fundamentals

---

## Prerequisites

- [Docker](../Docker/) — you must understand images, containers, and Compose before this module. Kubernetes schedules containers; if you don't know containers, K8s is just confusion.
- [Linux](../Linux/) — comfortable at the shell, understand processes and networking basics.
- [AWS](../AWS/) — helpful for the EKS context, not required for local labs.

Install the required tools before starting:

```bash
# kubectl - the Kubernetes CLI
brew install kubectl           # macOS
# or
curl -LO "https://dl.k8s.io/release/$(curl -s https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl"

# minikube - local single-node cluster
brew install minikube          # macOS
# or
curl -LO https://storage.googleapis.com/minikube/releases/latest/minikube-linux-amd64

# Verify
kubectl version --client
minikube version
```

---

## Notes

| Topic | File |
|-------|------|
| K8s Architecture & Core Concepts | [01-k8s-basics.md](./01-k8s-basics.md) |
| Pods, Deployments & Workloads | [02-pods-deployments.md](./02-pods-deployments.md) |
| Services & Networking | [03-services-networking.md](./03-services-networking.md) |
| ConfigMaps & Secrets | [04-configmaps-secrets.md](./04-configmaps-secrets.md) |
| Storage & Volumes | [05-storage-volumes.md](./05-storage-volumes.md) |
| Helm Package Manager | [06-helm-package-manager.md](./06-helm-package-manager.md) |
| RBAC & Security | [07-rbac-security.md](./07-rbac-security.md) |

---

## Labs

| Lab | Description |
|-----|-------------|
| [Lab 01](./lab-01-first-deployment.md) | Deploy, scale, update, and rollback an application |
| [Lab 02](./lab-02-services-ingress.md) | Expose apps with Services and Ingress |
| [Lab 03](./lab-03-stateful-application.md) | Deploy a stateful app with persistent storage |

---

## Module Project

**Deploy the Docker app from the previous module onto Kubernetes.**

By the end you will have:
- A multi-tier application (web + database) running in a cluster
- ConfigMaps and Secrets managing all configuration
- A Service and Ingress exposing the app to external traffic
- A PersistentVolumeClaim keeping the database data safe across pod restarts
- A Helm chart packaging the entire application

This is the bridge between "I run containers" and "I run production workloads."

---

## Next Module

06 — CI/CD → [../CICD/](../CICD/)
