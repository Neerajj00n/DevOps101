# Image Best Practices & Security

The difference between an amateur Dockerfile and a production-grade one isn't cleverness — it's discipline. Small images, pinned versions, non-root users, no secrets, scanned for CVEs. None of it is hard. Most of it is checklist work that beginners skip and seniors automate.

---

## The Checklist

Before any image goes to production:

- [ ] Pinned base image (`python:3.12.4-slim`, not `python:latest`)
- [ ] Multi-stage build — no compilers/toolchains in the final image
- [ ] Slim or distroless final stage
- [ ] `.dockerignore` excludes `.git`, `node_modules`, `.env`, etc.
- [ ] `USER` set to a non-root account
- [ ] No secrets in the image, in `ENV`, or in the build args
- [ ] `HEALTHCHECK` defined
- [ ] `LABEL`s for traceability (git SHA, build date, source)
- [ ] Image scanned (Trivy, Grype, or your registry's built-in scanner)
- [ ] Tagged with both an immutable version and a moving tag (`:1.4.2` + `:1.4`)

---

## Pin Everything

```dockerfile
# Bad — silently changes when upstream rebuilds
FROM python:3.12

# Better — at least the minor version is fixed
FROM python:3.12-slim

# Best — exact version, fully reproducible
FROM python:3.12.4-slim-bookworm

# Paranoid — pin to a content digest. The byte-exact image, forever.
FROM python:3.12.4-slim-bookworm@sha256:abcd1234...
```

Same goes for OS packages:

```dockerfile
# Bad
RUN apt-get update && apt-get install -y curl

# Good — version-pinned, no recommends, cache cleaned
RUN apt-get update && \
    apt-get install -y --no-install-recommends \
      curl=7.88.1-* \
      ca-certificates=20230311 && \
    rm -rf /var/lib/apt/lists/*
```

---

## Don't Run as Root

```dockerfile
# Debian/Ubuntu base
RUN groupadd --system app && useradd --system --gid app --home /app app
USER app

# Alpine base
RUN addgroup -S app && adduser -S -G app app
USER app

# Or just use a base image that's already non-root
FROM gcr.io/distroless/static-debian12:nonroot
```

If your app needs to bind to port 80 or 443, **don't** run as root to do it. Bind to a high port (8080, 8443) inside the container and map it externally with `-p 80:8080`, or use `setcap` / `CAP_NET_BIND_SERVICE`.

---

## No Secrets in Images

Anything in your image's layers is permanent — even if you `RUN rm -rf` it later, the secret is still in the previous layer. Anyone who pulls the image can read it.

**Wrong:**
```dockerfile
ENV API_KEY=sk_live_abc123          # baked into the image. Forever.
COPY .env /app/.env                  # ditto.
RUN echo "$DB_PASSWORD" > config     # ditto, in a layer.
```

**Right:**
- Pass secrets at **runtime** via env vars (`-e`, `--env-file`, Compose `environment:`).
- Use a secrets manager (AWS Secrets Manager, Vault, SSM Parameter Store) and fetch on container start.
- For build-time secrets (e.g. a private package registry token), use BuildKit secret mounts:

```dockerfile
# syntax=docker/dockerfile:1.7
RUN --mount=type=secret,id=npm_token \
    npm config set //registry.npmjs.org/:_authToken=$(cat /run/secrets/npm_token) && \
    npm ci
```

```bash
DOCKER_BUILDKIT=1 docker build \
  --secret id=npm_token,src=$HOME/.npmrc-token \
  -t myapp:1.0 .
```

The token is mounted into the build but never written to a layer.

---

## Smallest Practical Base

| Base | Approx size | Notes |
|------|-------------|-------|
| `ubuntu:22.04` | ~80 MB | Familiar, but big. Avoid for app images. |
| `debian:bookworm-slim` | ~80 MB | Same idea, smaller than full debian. |
| `python:3.12-slim` | ~50 MB | Slim variant of language images — good default. |
| `node:20-alpine` | ~50 MB | Alpine = musl libc. Watch for compatibility. |
| `alpine:3.20` | ~8 MB | Tiny. Uses `apk`, musl. Some Python wheels misbehave. |
| `gcr.io/distroless/...` | ~5–20 MB | No shell, no package manager. Minimal attack surface. |
| `scratch` | 0 MB | Empty. For static binaries (Go, Rust). |

A static Go binary on `scratch`:

```dockerfile
FROM golang:1.22 AS builder
WORKDIR /src
COPY . .
RUN CGO_ENABLED=0 go build -ldflags="-s -w" -o /out/app ./cmd/app

FROM scratch
COPY --from=builder /out/app /app
COPY --from=builder /etc/ssl/certs/ca-certificates.crt /etc/ssl/certs/
USER 65532:65532
ENTRYPOINT ["/app"]
```

That image is your binary plus CA certificates. Maybe 12 MB total. Nothing else can be exploited because nothing else is there.

---

## Tagging Strategy

Tag every production image with **both**:

1. An **immutable** tag: a git SHA or a semver. Never reused.
2. A **moving** tag: `:latest`, `:stable`, `:prod`. Points at whichever version is current.

```bash
docker build \
  -t myorg/myapp:$(git rev-parse --short HEAD) \
  -t myorg/myapp:1.4.2 \
  -t myorg/myapp:1.4 \
  -t myorg/myapp:latest \
  .

docker push myorg/myapp:$(git rev-parse --short HEAD)
docker push myorg/myapp:1.4.2
docker push myorg/myapp:1.4
docker push myorg/myapp:latest
```

Production deployments should reference the **immutable** tag (or, ideally, the digest). Then a rollback is just `image: myorg/myapp:abc1234` instead of `myorg/myapp:abc1235`.

---

## Labels for Traceability

```dockerfile
ARG GIT_SHA
ARG BUILD_DATE
ARG VERSION

LABEL org.opencontainers.image.source="https://github.com/myorg/myapp"
LABEL org.opencontainers.image.revision="${GIT_SHA}"
LABEL org.opencontainers.image.version="${VERSION}"
LABEL org.opencontainers.image.created="${BUILD_DATE}"
```

Six months later when you find a sketchy image running in prod and ask "where did this come from?", `docker inspect` will tell you.

---

## Scanning

```bash
# Trivy — open source, fast, scans images for CVEs
trivy image myorg/myapp:1.4.2

# Just HIGH and CRITICAL
trivy image --severity HIGH,CRITICAL myorg/myapp:1.4.2

# Fail a CI job if anything CRITICAL is found
trivy image --exit-code 1 --severity CRITICAL myorg/myapp:1.4.2

# Docker Scout (built into recent Docker Desktop)
docker scout cves myorg/myapp:1.4.2
```

Run scans in CI on every build. A new CVE published yesterday can affect an image you built six months ago — rebuild and redeploy regularly.

---

## Runtime Hardening

```bash
docker run -d \
  --name api \
  --read-only \                              # filesystem is read-only
  --tmpfs /tmp:rw,size=64m \                 # except for /tmp
  --cap-drop ALL \                           # drop all Linux capabilities
  --cap-add NET_BIND_SERVICE \               # add back only what's needed
  --security-opt no-new-privileges \         # block setuid escalation
  --user 1000:1000 \                         # explicit non-root
  --memory 512m --cpus 1 \                   # resource limits
  myorg/myapp:1.4.2
```

Compose equivalent:

```yaml
services:
  api:
    image: myorg/myapp:1.4.2
    read_only: true
    tmpfs:
      - /tmp:size=64m
    cap_drop: ["ALL"]
    cap_add: ["NET_BIND_SERVICE"]
    security_opt:
      - no-new-privileges:true
    user: "1000:1000"
    deploy:
      resources:
        limits:
          memory: 512M
          cpus: "1"
```

---

## Logs to stdout, Configs from Env

The two laws of containerised apps:

1. **Logs go to stdout/stderr.** Don't write to files inside the container — they vanish, and you can't `docker logs` them. If the app insists on writing files, mount them out.
2. **Config comes from environment variables (or mounted files).** No baked-in config, no editing files inside a running container.

If your app violates either, you'll fight the container model forever. Fix the app, not Docker.

---

## Key Insight for DevOps

The fundamental security mindset for containers: **your image is your supply chain**. Every base image, every `apt-get install`, every `pip install`, every `COPY . .` adds something to a tarball that will run with network access on your production servers.

Treat that supply chain like a real one:
- Pin the inputs.
- Audit what gets pulled in.
- Sign and verify what goes out.
- Rebuild and redeploy regularly to absorb upstream patches.

The image you ship is, in production, indistinguishable from the code you wrote. Hold it to the same standard.
