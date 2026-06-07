# Volumes & Networks

A container's filesystem disappears when the container is removed. Its network is isolated from the host by default. To run anything real — a database, an app that talks to another app — you need volumes (for persistence) and networks (for communication).

---

## Why You Need Volumes

```bash
docker run -d --name pg -e POSTGRES_PASSWORD=secret postgres:16
# ... write data, do work ...
docker rm -f pg
# All data is gone.
```

Containers are designed to be disposable. Volumes are the explicit place where state lives outside the container's lifecycle.

---

## Three Mount Types

| Type | Where the data lives | Use for |
|------|----------------------|---------|
| **Named volume** | Managed by Docker (`/var/lib/docker/volumes/...`) | Database files, app state |
| **Bind mount** | An exact path on the host | Local development (mount source code), config files |
| **tmpfs** | Host RAM (Linux only) | Secrets, scratch space — never written to disk |

---

## Named Volumes

```bash
# Create a volume
docker volume create pgdata

# Use it
docker run -d \
  --name pg \
  -e POSTGRES_PASSWORD=secret \
  -v pgdata:/var/lib/postgresql/data \
  postgres:16

# List, inspect, remove
docker volume ls
docker volume inspect pgdata
docker volume rm pgdata          # only works if no container is using it

# Reclaim unused volumes
docker volume prune
```

Now you can `docker rm -f pg` and recreate the container — the data survives.

---

## Bind Mounts (Local Dev)

```bash
# Mount your source code into the container so changes show up live
docker run -d \
  --name dev \
  -p 3000:3000 \
  -v "$(pwd)":/app \
  -w /app \
  node:20-alpine npm run dev
```

The container reads/writes the *exact same files* on your host. Useful in development; risky in production (host paths leak machine-specific assumptions, and you can mount sensitive paths like `/etc` by accident).

```bash
# Read-only bind mount — safer
docker run -v /etc/myapp/config.yml:/app/config.yml:ro myapp
```

---

## tmpfs

```bash
docker run --tmpfs /tmp:size=64m,mode=1777 myapp
```

Anything written to `/tmp` lives in RAM, vanishes when the container stops, and never touches disk. Good for ephemeral secrets and high-write scratch space.

---

## Networks

By default Docker creates three networks:

```bash
docker network ls
# NETWORK ID   NAME      DRIVER    SCOPE
# xxxx         bridge    bridge    local      ← default for `docker run`
# xxxx         host      host      local      ← container shares host network
# xxxx         none      null      local      ← no networking at all
```

The default `bridge` network is fine for one-off containers but **doesn't give you DNS-based service discovery**. For anything more than a single container, create a user-defined bridge.

---

## User-Defined Bridge Network

```bash
# Create a network
docker network create app-net

# Run a database on it
docker run -d \
  --name db \
  --network app-net \
  -e POSTGRES_PASSWORD=secret \
  -v pgdata:/var/lib/postgresql/data \
  postgres:16

# Run an app on the same network — it can reach the db by name!
docker run -d \
  --name api \
  --network app-net \
  -e DATABASE_URL=postgres://postgres:secret@db:5432/postgres \
  -p 8080:8080 \
  myapi:1.0
```

Inside the `api` container, the hostname `db` resolves to the database container's IP. This is the magic of user-defined bridges: built-in DNS.

---

## Publishing Ports

```bash
docker run -p 8080:80 nginx           # 8080 on host → 80 in container
docker run -p 127.0.0.1:8080:80 nginx # only listen on localhost (safer!)
docker run -P nginx                   # publish all EXPOSEd ports to random host ports
docker port web                        # show what mappings exist for a container
```

`-p 8080:80` opens 8080 on **all** host interfaces, which on a public server means the whole internet. Always bind to `127.0.0.1` unless you really mean to expose it.

---

## Network Drivers (Quick Reference)

| Driver | Use for |
|--------|---------|
| `bridge` | Single host. The default. Use a user-defined bridge for app stacks. |
| `host` | Container shares the host's network namespace. No isolation, no port mapping. Useful for high-throughput, but rare. |
| `none` | No network at all. Useful for batch jobs that don't need network. |
| `overlay` | Multi-host (Swarm/Kubernetes). |
| `macvlan` | Container appears as a physical device on your LAN. Niche. |

---

## Inspecting Networking

```bash
# What network is a container on, and what's its IP?
docker inspect -f \
  '{{range $k, $v := .NetworkSettings.Networks}}{{$k}}={{$v.IPAddress}}{{"\n"}}{{end}}' \
  api

# All containers on a network
docker network inspect app-net

# Connect a running container to another network
docker network connect monitoring api
docker network disconnect monitoring api
```

---

## Backing Up a Volume

There's no built-in `docker volume backup` — but a one-liner using a throwaway container does it:

```bash
# Backup pgdata to a tarball on the host
docker run --rm \
  -v pgdata:/data:ro \
  -v "$(pwd)":/backup \
  alpine \
  tar czf /backup/pgdata-$(date +%F).tar.gz -C /data .

# Restore
docker run --rm \
  -v pgdata:/data \
  -v "$(pwd)":/backup \
  alpine \
  sh -c 'cd /data && tar xzf /backup/pgdata-2026-06-07.tar.gz'
```

This trick — "spin up a tiny container that mounts both the volume and a host path" — is how almost all volume manipulation is done.

---

## Key Insight for DevOps

The two questions to ask yourself for any container:

1. **What state does this container have, and where does it live?** If the answer is "inside the container", you have a bug — pull it out into a volume or an external service (RDS, S3, Redis).
2. **Who can talk to whom?** Default-deny: containers should be on a private network with only specific ports exposed to the host (and almost nothing exposed directly to the internet — that's the load balancer's job).

Get those two right and you've avoided 90% of "why doesn't my container work in production?" problems.
