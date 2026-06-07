# Running Containers

Once you have an image, `docker run` turns it into a running process. Most day-to-day Docker work is just variations on `run`, `exec`, `logs`, and `ps`.

---

## docker run — The Workhorse

```bash
# Simplest possible run
docker run hello-world

# Interactive shell in a fresh container
docker run -it --rm ubuntu:22.04 bash

# Background (detached) web server with port mapping
docker run -d \
  --name web \
  -p 8080:80 \
  nginx:1.27-alpine

# Visit http://localhost:8080
```

The flags you will use constantly:

| Flag | Purpose |
|------|---------|
| `-d` | Detached — run in background |
| `-it` | Interactive + TTY — for shells |
| `--rm` | Auto-remove the container when it exits |
| `--name X` | Give the container a name (otherwise random: `clever_einstein`) |
| `-p HOST:CONTAINER` | Publish a port (e.g. `-p 8080:80`) |
| `-e KEY=VALUE` | Set an environment variable |
| `--env-file .env` | Load env vars from a file |
| `-v HOST:CONTAINER` | Mount a volume |
| `--network mynet` | Attach to a custom network |
| `--restart unless-stopped` | Auto-restart on crash and host reboot |

---

## Listing & Inspecting

```bash
# Running containers
docker ps

# All containers — including stopped
docker ps -a

# Just IDs (useful for scripting)
docker ps -q

# Detailed JSON for a container
docker inspect web

# A specific field with a Go template
docker inspect -f '{{ .NetworkSettings.IPAddress }}' web

# Live resource usage (CPU, memory, network)
docker stats
docker stats --no-stream      # one-shot snapshot
```

---

## Logs

```bash
# Print all logs so far
docker logs web

# Follow (tail -f style)
docker logs -f web

# Last 100 lines, with timestamps, since 10 minutes ago
docker logs --tail 100 -t --since 10m web
```

A container's logs are whatever the main process wrote to stdout/stderr. This is why containerised apps should log to stdout, not to files inside the container.

---

## Exec — Get a Shell Inside a Running Container

```bash
# Open a bash shell inside the running 'web' container
docker exec -it web bash

# Run a one-off command
docker exec web nginx -t          # check nginx config
docker exec web ls /etc/nginx
```

If `bash` isn't installed (common on `alpine` images), use `sh`:
```bash
docker exec -it web sh
```

`exec` is for debugging, not deployment. The container's main process is whatever was started by `CMD`/`ENTRYPOINT` — `exec` just attaches another process inside the same namespaces.

---

## Stopping & Removing

```bash
# Graceful stop — sends SIGTERM, then SIGKILL after 10s
docker stop web

# Immediate kill
docker kill web

# Restart
docker restart web

# Remove a stopped container
docker rm web

# Force-remove a running container
docker rm -f web

# Stop and remove ALL containers (careful!)
docker rm -f $(docker ps -aq)
```

---

## Environment Variables & Configuration

```bash
docker run -d \
  --name app \
  -e DB_HOST=db.internal \
  -e DB_PORT=5432 \
  -e LOG_LEVEL=info \
  myapp:1.0

# Or from a file
cat > .env <<'EOF'
DB_HOST=db.internal
DB_PORT=5432
LOG_LEVEL=info
EOF

docker run -d --name app --env-file .env myapp:1.0
```

12-factor apps configure themselves entirely from env vars. Never bake config into an image.

---

## Resource Limits

By default a container can consume all the host's CPU and RAM. On a shared host this is dangerous.

```bash
docker run -d \
  --name app \
  --cpus="1.5" \
  --memory="512m" \
  --memory-swap="512m" \
  myapp:1.0
```

`docker stats` will show whether you're hitting the limits.

---

## Restart Policies

```bash
docker run -d --restart=unless-stopped --name web nginx
```

| Policy | When it restarts |
|--------|------------------|
| `no` (default) | Never |
| `on-failure[:max]` | Only on non-zero exit |
| `always` | Always — even if you `docker stop` it (then start the daemon) |
| `unless-stopped` | Like `always`, but respects manual `docker stop` |

For a single-host production setup, `unless-stopped` is usually the right choice.

---

## Container Lifecycle

```
       ┌─────────┐  docker run   ┌──────────┐
created│         │──────────────▶│ running  │
       └─────────┘               └──────────┘
                                  │   ▲    │
                          stop / kill│   │  start / restart
                                  ▼   │    ▼
                              ┌──────────┐
                              │ exited   │──── rm ──▶ gone
                              └──────────┘
```

A stopped container still exists — it has its filesystem layer and exit code. You can restart it. Only `docker rm` truly deletes it.

---

## Key Insight for DevOps

Containers are not VMs — they're foreground processes. When the main process exits, the container exits. If your container starts and immediately stops, the first thing to check is `docker logs <name>`: usually the entrypoint crashed, or you wrote something like `CMD service nginx start` (which forks and exits, killing the container).

Containers should run **one** main foreground process. If you need multiple processes, that's a sign you should use multiple containers (or, in advanced cases, a process supervisor like `tini` or `s6-overlay`).
