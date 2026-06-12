# Services & Networking

Kubernetes Pods are ephemeral — they come and go, and their IPs change. Services provide a stable network identity in front of a set of Pods. They are the foundation of all in-cluster and external communication.

---

## The Problem Services Solve

```
Before Services:
  App → hardcoded IP 172.17.0.4 → Pod (but Pod restarts → gets new IP 172.17.0.7 → app breaks)

After Services:
  App → my-service:80 (stable DNS name + IP) → kube-proxy → Pod (any IP, any node)
```

A Service uses a label selector to find its target Pods. kube-proxy on each node maintains iptables rules to forward traffic.

---

## Service Types

### ClusterIP (default)

Exposes the Service on an internal cluster IP. Only reachable from within the cluster.

```yaml
apiVersion: v1
kind: Service
metadata:
  name: backend-svc
spec:
  type: ClusterIP        # default, can omit
  selector:
    app: backend         # forwards to pods with this label
  ports:
  - port: 80             # port the Service listens on
    targetPort: 8080     # port on the Pod
    protocol: TCP
```

```bash
# From inside the cluster, you can reach it as:
# backend-svc            (within same namespace)
# backend-svc.default    (across namespaces, short form)
# backend-svc.default.svc.cluster.local   (FQDN)
curl http://backend-svc/api/health
```

### NodePort

Exposes the Service on a static port on every node's IP. Accessible from outside the cluster.

```yaml
apiVersion: v1
kind: Service
metadata:
  name: frontend-svc
spec:
  type: NodePort
  selector:
    app: frontend
  ports:
  - port: 80
    targetPort: 3000
    nodePort: 30080    # 30000-32767 range; omit to auto-assign
```

Access via `<NodeIP>:30080`. Useful for development. **Not recommended for production** — exposes the node directly.

### LoadBalancer

Creates an external load balancer in cloud environments (AWS ELB, GCP LB, Azure LB). Builds on NodePort.

```yaml
apiVersion: v1
kind: Service
metadata:
  name: web-svc
  annotations:
    service.beta.kubernetes.io/aws-load-balancer-type: "nlb"  # AWS-specific
spec:
  type: LoadBalancer
  selector:
    app: web
  ports:
  - port: 80
    targetPort: 8080
```

```bash
kubectl get svc web-svc    # EXTERNAL-IP appears after LB is provisioned (1-2 minutes)
```

### ExternalName

Maps a Service to a DNS name outside the cluster. Useful for referencing external databases or services.

```yaml
apiVersion: v1
kind: Service
metadata:
  name: my-database
spec:
  type: ExternalName
  externalName: mydb.example.com
```

---

## Service Discovery and DNS

Every Service gets a DNS entry via CoreDNS (built into every cluster):

```
<service-name>.<namespace>.svc.cluster.local
```

```bash
# From a pod, test DNS resolution
kubectl exec -it my-pod -- nslookup backend-svc
kubectl exec -it my-pod -- curl http://backend-svc:80
```

Pod DNS follows the same pattern:
```
<pod-ip-dashes>.<namespace>.pod.cluster.local
# e.g. 172-17-0-4.default.pod.cluster.local
```

---

## Endpoints and EndpointSlices

When you create a Service with a selector, Kubernetes automatically creates an Endpoints object listing all matching Pod IPs.

```bash
kubectl get endpoints backend-svc
# NAME          ENDPOINTS                     AGE
# backend-svc   172.17.0.4:8080,172.17.0.5:8080   5m
```

If `ENDPOINTS` shows `<none>`, your selector doesn't match any pods — check labels.

---

## Ingress

Services of type LoadBalancer cost money (one LB per service). Ingress uses a single load balancer to route to many services based on host or path.

```
Internet
    │
    ▼
LoadBalancer (1 LB, 1 IP, much cheaper)
    │
    ▼
Ingress Controller (nginx, traefik, AWS ALB controller...)
    │
    ├─ /api/*     → backend-svc:80
    ├─ /static/*  → static-svc:80
    └─ /*         → frontend-svc:80
```

### Install an Ingress Controller (nginx)

```bash
# minikube
minikube addons enable ingress

# Standalone
kubectl apply -f https://raw.githubusercontent.com/kubernetes/ingress-nginx/controller-v1.10.0/deploy/static/provider/cloud/deploy.yaml

kubectl get pods -n ingress-nginx
```

### Ingress Resource

```yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: my-ingress
  annotations:
    nginx.ingress.kubernetes.io/rewrite-target: /
spec:
  ingressClassName: nginx
  rules:
  - host: myapp.example.com
    http:
      paths:
      - path: /api
        pathType: Prefix
        backend:
          service:
            name: backend-svc
            port:
              number: 80
      - path: /
        pathType: Prefix
        backend:
          service:
            name: frontend-svc
            port:
              number: 80
  tls:                              # HTTPS
  - hosts:
    - myapp.example.com
    secretName: myapp-tls-secret    # TLS cert stored as a Secret
```

```bash
kubectl get ingress
kubectl describe ingress my-ingress
```

---

## Network Policies

By default, all Pods in a cluster can communicate with all other Pods — including across namespaces. Network Policies restrict this.

```
Default: Pod A → (any traffic) → Pod B ✓

With NetworkPolicy:
  Pod A → backend only if labeled app=frontend ✗ (denied by default-deny)
  Pod frontend → backend:8080 ✓ (allowed by policy)
```

### Default deny all ingress

```yaml
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: default-deny-ingress
  namespace: production
spec:
  podSelector: {}     # applies to all pods in namespace
  policyTypes:
  - Ingress
```

### Allow specific traffic

```yaml
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: allow-frontend-to-backend
spec:
  podSelector:
    matchLabels:
      app: backend         # this policy applies to backend pods
  policyTypes:
  - Ingress
  ingress:
  - from:
    - podSelector:
        matchLabels:
          app: frontend    # only allow traffic from frontend pods
    ports:
    - protocol: TCP
      port: 8080
```

**Note:** Network Policies require a CNI plugin that supports them (Calico, Cilium, Weave). minikube uses kindnet by default which does NOT enforce NetworkPolicy.

---

## DNS Troubleshooting

```bash
# Run a debug pod with network tools
kubectl run debug --image=nicolaka/netshoot -it --rm -- bash

# Inside the debug pod:
nslookup backend-svc
nslookup backend-svc.default.svc.cluster.local
dig backend-svc.default.svc.cluster.local
curl -v http://backend-svc:80
```

Common issues:
- `nslookup` fails → CoreDNS down: `kubectl get pods -n kube-system -l k8s-app=kube-dns`
- Service not reachable → check selector matches pod labels
- Connection refused → app not listening on the targetPort
- Timeout → NetworkPolicy blocking traffic

---

## Networking Model Summary

Kubernetes networking follows 3 fundamental rules:
1. Every Pod gets its own unique IP address
2. All Pods can communicate with all other Pods without NAT
3. Agents on a node can communicate with all Pods on that node

```
Pod-to-Pod:     uses Pod CIDR (overlay network via CNI)
Pod-to-Service: uses Service CIDR (iptables/IPVS via kube-proxy)
External:       NodePort or LoadBalancer or Ingress
```
