# Images & the Container Model

A container is a Linux process running in isolation. Docker doesn't invent a new kind of OS — it uses kernel features (namespaces, cgroups, overlay filesystems) that have been in Linux for years, and wraps them in a friendly CLI and a packaging format.

---

## Container vs Virtual Machine

```
┌──────────────────────┐      ┌──────────────────────┐
│  App A   App B   App C│      │  App A   App B   App C│
│  Bins/   Bins/   Bins/│      │ Guest OS Guest OS Guest OS│
│  Libs    Libs    Libs │      │   Bins    Bins    Bins│
│──────────────────────│      │──────────────────────│
│   Docker Engine      │      │     Hypervisor       │
│──────────────────────│      │──────────────────────│
│      Host OS         │      │      Host OS         │
│──────────────────────│      │──────────────────────│
│      Hardware        │      │      Hardware        │
└──────────────────────┘      └──────────────────────┘
       Containers                       VMs
```

- **VM** — full guest OS per app. Heavy (GBs), slow boot (minutes), strong isolation.
- **Container** — shares the host kernel. Light (MBs), fast boot (seconds), process-level isolation.

You can run hundreds of containers on a host that would barely fit ten VMs.

---

## Image vs Container

| | Image | Container |
|---|-------|-----------|
| What | A read-only template | A running (or stopped) instance of an image |
| Analogy | A class | An object |
| Lives in | Layers on disk | Memory + a thin writable layer |
| Created by | `docker build` | `docker run` |

You can launch many containers from one image. Each gets its own filesystem layer on top.

---

## Layers

Every line in a Dockerfile produces a layer. Layers are cached and shared across images, which is why pulling a new image is often almost instant — most of its layers are already on your machine.

```
┌─────────────────────────────┐  ← thin writable layer (one per container)
├─────────────────────────────┤
│ COPY app/ /app/             │  ← image layers (read-only, shared)
├─────────────────────────────┤
│ RUN pip install -r req.txt  │
├─────────────────────────────┤
│ FROM python:3.12-slim       │
└─────────────────────────────┘
```

Inspect them:
```bash
docker history python:3.12-slim
docker image inspect python:3.12-slim
```

---

## Image Naming

```
[registry/]namespace/repository[:tag]
```

```
nginx                                  → docker.io/library/nginx:latest
nginx:1.27-alpine                      → specific tag from Docker Hub
ghcr.io/myorg/myapp:v1.2.3             → GitHub Container Registry
123456789012.dkr.ecr.ap-south-1.amazonaws.com/myapp:prod   → ECR
```

If you don't specify a tag, Docker assumes `:latest`. **Never rely on `:latest` in production** — it changes silently. Pin to a version or, better, a digest:

```bash
nginx@sha256:abcd1234...   # immutable, byte-exact
```

---

## Pulling, Listing, Removing

```bash
# Pull an image from a registry
docker pull nginx:1.27-alpine

# List images on this host
docker images
docker image ls

# Remove an image (must have no containers using it)
docker rmi nginx:1.27-alpine

# Reclaim space — removes unused images, networks, build cache
docker system prune -a
docker system df       # how much disk are containers/images using?
```

---

## Where Images Live

By default, Docker stores everything under `/var/lib/docker/` on Linux. Each layer is a directory, and overlayfs stacks them into the filesystem the container sees.

You almost never poke around in there directly — but knowing it exists demystifies "where did my 30 GB of disk go?" The answer is usually a swarm of dangling images and stopped containers.

```bash
docker system df -v   # detailed breakdown: images, containers, volumes, build cache
```

---

## Key Insight for DevOps

An image is just a tarball of filesystem layers plus a JSON manifest. There is nothing magical inside. You can `docker save` an image to a tar file, scp it to another host, and `docker load` it there. Understanding that an image is *data*, not *code*, is what unlocks the rest of containers — registries, CI/CD pipelines, and supply-chain security.
