# Writing Dockerfiles

A Dockerfile is a recipe — a sequence of instructions that produces an image. Good Dockerfiles are small, cacheable, reproducible, and don't run as root. Most production Dockerfiles you'll read are 30–60 lines.

---

## Hello World Dockerfile

```dockerfile
# syntax=docker/dockerfile:1.7

FROM python:3.12-slim

WORKDIR /app

COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

COPY . .

EXPOSE 8000
CMD ["python", "-m", "http.server", "8000"]
```

Build and run it:

```bash
docker build -t myapp:1.0 .
docker run --rm -p 8000:8000 myapp:1.0
```

---

## The Core Instructions

| Instruction | What it does |
|-------------|--------------|
| `FROM` | Base image. Always the first instruction. |
| `WORKDIR` | Set the working directory (creates it if missing). |
| `COPY` | Copy files from the build context into the image. |
| `ADD` | Like `COPY`, but also unpacks tarballs and fetches URLs. Prefer `COPY`. |
| `RUN` | Execute a command at build time. Each `RUN` is a layer. |
| `ENV` | Set an env var (persists at runtime). |
| `ARG` | Build-time variable (doesn't persist into the final image). |
| `EXPOSE` | Documents which port the container listens on. Doesn't actually publish it — that's `-p` at run time. |
| `USER` | Switch to a non-root user. |
| `ENTRYPOINT` | The "binary" of the container — fixed. |
| `CMD` | The "default arguments" — overridable on `docker run`. |
| `HEALTHCHECK` | How Docker should check the container is alive. |

---

## ENTRYPOINT vs CMD

This trips everyone up at first.

```dockerfile
ENTRYPOINT ["python"]
CMD ["app.py"]
```

- `docker run myapp` → runs `python app.py`
- `docker run myapp test.py` → runs `python test.py` (CMD overridden)
- `docker run --entrypoint /bin/sh myapp` → runs `sh` (ENTRYPOINT overridden)

Rule of thumb:
- Use **`ENTRYPOINT`** for the thing that should always run (the binary).
- Use **`CMD`** for the default arguments.
- Always use the **exec form** (`["arg1", "arg2"]`) — the shell form (`CMD python app.py`) wraps everything in `/bin/sh -c` and breaks signal handling.

---

## Layer Caching — Order Matters

Each instruction is cached. Docker reuses a cached layer if the instruction *and* its inputs haven't changed. Once a layer is invalidated, every subsequent layer rebuilds.

**Bad — invalidates the dependency cache on every code change:**
```dockerfile
COPY . .
RUN pip install -r requirements.txt
```

**Good — dependencies cached separately from code:**
```dockerfile
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt
COPY . .
```

Now changing `app.py` only invalidates the final `COPY` — the dependency install (the slow step) stays cached.

**Rule:** copy and install dependencies *before* copying source code.

---

## Multi-Stage Builds

The single biggest tool for shrinking images. Build in one stage with all the tooling; copy only the artefacts into a clean final stage.

```dockerfile
# syntax=docker/dockerfile:1.7

# ── Stage 1: build ─────────────────────────────
FROM golang:1.22 AS builder
WORKDIR /src
COPY go.mod go.sum ./
RUN go mod download
COPY . .
RUN CGO_ENABLED=0 GOOS=linux go build -o /out/app ./cmd/app

# ── Stage 2: runtime ───────────────────────────
FROM gcr.io/distroless/static-debian12:nonroot
COPY --from=builder /out/app /app
USER nonroot:nonroot
EXPOSE 8080
ENTRYPOINT ["/app"]
```

Final image: ~15 MB instead of ~900 MB. No compiler, no shell, no package manager, no attack surface.

Same pattern for Node:

```dockerfile
FROM node:20-alpine AS builder
WORKDIR /app
COPY package*.json ./
RUN npm ci
COPY . .
RUN npm run build

FROM node:20-alpine
WORKDIR /app
ENV NODE_ENV=production
COPY package*.json ./
RUN npm ci --omit=dev && npm cache clean --force
COPY --from=builder /app/dist ./dist
USER node
EXPOSE 3000
CMD ["node", "dist/server.js"]
```

---

## .dockerignore

Without it, your entire build context (including `.git`, `node_modules`, `.env`) is sent to the Docker daemon on every build — slow, and a security risk.

```
# .dockerignore
.git
.gitignore
node_modules
**/__pycache__
*.log
.env
.env.*
*.md
.vscode
.idea
Dockerfile*
docker-compose*
```

---

## Run as Non-Root

By default, containers run as root. If an attacker escapes the container, they're root on the host (with caveats — but assume the worst). Always switch to a non-root user.

```dockerfile
RUN addgroup --system app && adduser --system --ingroup app app
USER app
```

Distroless `:nonroot` images do this for you. So does `node:20-alpine` (`USER node`).

---

## Healthchecks

```dockerfile
HEALTHCHECK --interval=30s --timeout=3s --start-period=10s --retries=3 \
  CMD wget -qO- http://localhost:8080/health || exit 1
```

`docker ps` will show the container as `healthy`, `unhealthy`, or `starting`. Compose, swarm, and orchestrators use this to decide whether to route traffic.

---

## Build Commands

```bash
# Basic build
docker build -t myapp:1.0 .

# Tag multiple things at once
docker build -t myapp:1.0 -t myapp:latest .

# Build with build args
docker build --build-arg APP_VERSION=1.2.3 -t myapp:1.2.3 .

# Specify a Dockerfile in a different location
docker build -f docker/Dockerfile.prod -t myapp:prod .

# No cache (force a clean build)
docker build --no-cache -t myapp:1.0 .

# BuildKit — modern builder, parallel stages, better caching (default in recent Docker)
DOCKER_BUILDKIT=1 docker build -t myapp:1.0 .

# Multi-platform build (requires buildx)
docker buildx build --platform linux/amd64,linux/arm64 -t myorg/myapp:1.0 --push .
```

---

## Key Insight for DevOps

A 1.2 GB image and a 60 MB image do the same thing — but the 60 MB image:
- Pulls 20× faster on every deploy
- Has 20× less surface area for CVEs
- Boots faster on cold scale-up
- Costs less in egress and storage

Multi-stage + a slim base image (`alpine`, `slim`, or `distroless`) is the difference. Aim for **<200 MB** for app images. If you're above 500 MB, something is wrong.
