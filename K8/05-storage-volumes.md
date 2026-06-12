# Storage & Volumes

Containers are ephemeral by default — when a container restarts, everything written to its filesystem is gone. Kubernetes volumes decouple storage from the container lifecycle, allowing data to survive pod restarts, be shared between containers, and persist even when pods are rescheduled to different nodes.

---

## Volume Lifecycle

```
Container filesystem:
  - Lives and dies with the container
  - Lost on every restart

Pod Volume:
  - Lives as long as the Pod
  - Shared between containers in the same Pod
  - Lost when the Pod is deleted

PersistentVolume:
  - Independent of any Pod
  - Data survives Pod deletion, rescheduling, node loss
```

---

## Ephemeral Volumes

### emptyDir

Created when a Pod is assigned to a node, deleted when the Pod is removed. Useful for temporary scratch space and sharing data between containers in a Pod.

```yaml
spec:
  volumes:
  - name: scratch
    emptyDir: {}
  - name: shared-data
    emptyDir:
      medium: Memory    # store in RAM (tmpfs) — faster, but uses node memory
      sizeLimit: 100Mi
  containers:
  - name: writer
    image: busybox
    command: ["sh", "-c", "while true; do date >> /data/output.txt; sleep 5; done"]
    volumeMounts:
    - name: shared-data
      mountPath: /data
  - name: reader
    image: busybox
    command: ["sh", "-c", "tail -f /data/output.txt"]
    volumeMounts:
    - name: shared-data
      mountPath: /data
```

### hostPath

Mounts a file or directory from the **host node's** filesystem. Use with caution — it creates tight coupling to the node.

```yaml
volumes:
- name: host-logs
  hostPath:
    path: /var/log/pods
    type: Directory    # Directory, File, DirectoryOrCreate, FileOrCreate
```

Common use: DaemonSets that need access to host files (log collectors reading from `/var/log`).

---

## Persistent Storage

### The Three Objects

```
StorageClass  →  How to provision storage (which EBS type, which NFS server)
     │
     ▼
PersistentVolume (PV)  →  An actual piece of storage in the cluster
     │
     ▼
PersistentVolumeClaim (PVC)  →  A request for storage from a user/app
```

### StorageClass

Defines how storage is provisioned. Different classes for different needs (SSD, HDD, different IOPS).

```yaml
apiVersion: storage.k8s.io/v1
kind: StorageClass
metadata:
  name: fast
  annotations:
    storageclass.kubernetes.io/is-default-class: "true"  # used if PVC doesn't specify
provisioner: ebs.csi.aws.com        # AWS EBS CSI driver
parameters:
  type: gp3
  iops: "3000"
  throughput: "125"
reclaimPolicy: Delete               # Delete or Retain when PVC is deleted
allowVolumeExpansion: true
volumeBindingMode: WaitForFirstConsumer  # don't provision until pod is scheduled
```

```bash
kubectl get storageclass
kubectl describe storageclass fast
```

### PersistentVolume (PV)

A piece of storage in the cluster provisioned by an admin or dynamically by a StorageClass.

```yaml
# Manual (static) provisioning — rarely needed with dynamic provisioning
apiVersion: v1
kind: PersistentVolume
metadata:
  name: my-pv
spec:
  capacity:
    storage: 10Gi
  accessModes:
  - ReadWriteOnce
  reclaimPolicy: Retain
  storageClassName: fast
  awsElasticBlockStore:
    volumeID: vol-0abcd1234
    fsType: ext4
```

### PersistentVolumeClaim (PVC)

A request for storage by a user. Kubernetes binds it to a matching PV.

```yaml
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: postgres-data
spec:
  accessModes:
  - ReadWriteOnce    # see Access Modes section
  storageClassName: fast
  resources:
    requests:
      storage: 10Gi
```

```bash
kubectl get pvc
# NAME            STATUS   VOLUME                  CAPACITY   ACCESS MODES
# postgres-data   Bound    pvc-abc123...            10Gi       RWO
```

### Using a PVC in a Pod

```yaml
spec:
  volumes:
  - name: db-storage
    persistentVolumeClaim:
      claimName: postgres-data   # reference the PVC
  containers:
  - name: postgres
    image: postgres:16-alpine
    volumeMounts:
    - name: db-storage
      mountPath: /var/lib/postgresql/data
```

---

## Access Modes

| Mode | Short | Meaning |
|------|-------|---------|
| `ReadWriteOnce` | RWO | One node can mount read-write. Most block storage (EBS, GCE PD). |
| `ReadOnlyMany` | ROX | Many nodes can mount read-only. |
| `ReadWriteMany` | RWX | Many nodes can mount read-write. Requires NFS, EFS, CephFS, etc. |
| `ReadWriteOncePod` | RWOP | Only one Pod can mount read-write. Stricter than RWO. |

**EBS (AWS):** RWO only. For RWX, use EFS (NFS-based).

---

## Reclaim Policies

What happens to the PV when the PVC is deleted:

| Policy | Behavior |
|--------|----------|
| `Delete` | Deletes the underlying storage (EBS volume, etc.) |
| `Retain` | Keeps the storage. Must be manually reclaimed. |
| `Recycle` | Deprecated. Ran `rm -rf` on the volume. |

Use `Retain` for production databases — you don't want an accidental `kubectl delete pvc` to destroy your data.

---

## Volume Expansion

If the StorageClass allows it:

```bash
# Edit the PVC to request more storage
kubectl edit pvc postgres-data
# Change: storage: 10Gi → storage: 20Gi

# Verify
kubectl describe pvc postgres-data
```

Expanding may require the pod to restart, depending on the storage driver.

---

## CSI — Container Storage Interface

Modern Kubernetes uses CSI drivers to interface with storage providers. Install the appropriate driver for your environment:

```bash
# AWS EBS CSI Driver (already included in EKS)
kubectl get pods -n kube-system -l app.kubernetes.io/name=aws-ebs-csi-driver

# Check available CSI drivers
kubectl get csidrivers
```

Popular CSI drivers:
- `ebs.csi.aws.com` — AWS EBS
- `efs.csi.aws.com` — AWS EFS (RWX)
- `disk.csi.azure.com` — Azure Disk
- `pd.csi.storage.gke.io` — GCP Persistent Disk
- `rook-ceph.rbd.csi.ceph.com` — Rook Ceph (self-hosted)

---

## StatefulSet Storage

StatefulSets use `volumeClaimTemplates` to create a unique PVC per pod:

```yaml
apiVersion: apps/v1
kind: StatefulSet
metadata:
  name: postgres
spec:
  serviceName: postgres
  replicas: 3
  template:
    spec:
      containers:
      - name: postgres
        image: postgres:16-alpine
        volumeMounts:
        - name: data
          mountPath: /var/lib/postgresql/data
  volumeClaimTemplates:
  - metadata:
      name: data
    spec:
      accessModes: ["ReadWriteOnce"]
      storageClassName: fast
      resources:
        requests:
          storage: 10Gi
```

Each replica gets its own PVC:
```
data-postgres-0   → 10Gi
data-postgres-1   → 10Gi
data-postgres-2   → 10Gi
```

Deleting the StatefulSet does NOT delete the PVCs (data is safe). Delete them manually if no longer needed.

---

## Backup Strategies

### Volume Snapshots (CSI)

```yaml
apiVersion: snapshot.storage.k8s.io/v1
kind: VolumeSnapshot
metadata:
  name: postgres-snapshot-20260612
spec:
  volumeSnapshotClassName: csi-aws-vsc
  source:
    persistentVolumeClaimName: postgres-data
```

```bash
kubectl get volumesnapshot
```

### Restore from Snapshot

```yaml
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: postgres-data-restored
spec:
  dataSource:
    name: postgres-snapshot-20260612
    kind: VolumeSnapshot
    apiGroup: snapshot.storage.k8s.io
  accessModes:
  - ReadWriteOnce
  resources:
    requests:
      storage: 10Gi
```

---

## Debugging Storage Issues

```bash
# Check PVC status
kubectl get pvc
kubectl describe pvc my-pvc

# Common issues:
# STATUS: Pending → no matching PV or StorageClass issue
kubectl describe pvc my-pvc  # look at Events section

# Check if StorageClass exists
kubectl get storageclass

# Check PV status
kubectl get pv
kubectl describe pv my-pv

# Check CSI driver pods
kubectl get pods -n kube-system | grep csi
```

Common PVC stuck `Pending` causes:
- StorageClass name doesn't match
- No node matches `volumeBindingMode: WaitForFirstConsumer` (no pod using the PVC)
- CSI driver not installed
- Insufficient capacity in the storage backend
