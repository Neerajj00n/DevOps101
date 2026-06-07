# Docker Compose

Once your app needs more than one container — a web service plus a database, plus a cache, plus a worker — chaining `docker run` commands gets painful. Compose lets you describe the entire stack in a single YAML file and bring it up with one command.

Compose is for **single-host** orchestration: local dev, small staging environments, simple production deploys. For multi-host clusters, you graduate to Kubernetes.

---

## Hello Compose

```yaml
# docker-compose.yml
services:
  web:
    image: nginx:1.27-alpine
    ports:
      - "8080:80"
```

```bash
docker compose up -d
docker compose ps
docker compose logs -f
docker compose down
```

That's it. `up -d` starts the stack in the background. `down` stops and removes everything (containers, the default network — but **not** volumes, by design).

---

## A Realistic Stack — Web + Postgres

```yaml
# docker-compose.yml
services:
  db:
    image: postgres:16-alpine
    restart: unless-stopped
    environment:
      POSTGRES_USER: app
      POSTGRES_PASSWORD: ${DB_PASSWORD:?DB_PASSWORD is required}
      POSTGRES_DB: appdb
    volumes:
      - pgdata:/var/lib/postgresql/data
    healthcheck:
      test: ["CMD-SHELL", "pg_isready -U app -d appdb"]
      interval: 5s
      timeout: 3s
      retries: 5

  api:
    build:
      context: ./api
      dockerfile: Dockerfile
    image: myorg/myapi:dev
    restart: unless-stopped
    environment:
      DATABASE_URL: postgres://app:${DB_PASSWORD}@db:5432/appdb
      LOG_LEVEL: info
    ports:
      - "127.0.0.1:8080:8080"
    depends_on:
      db:
        condition: service_healthy

volumes:
  pgdata:
```

Bring it up:

```bash
echo 'DB_PASSWORD=supersecret' > .env
docker compose up -d --build

# Check
docker compose ps
docker compose logs -f api

# Tear down (keeps the volume — your data survives)
docker compose down

# Tear down and delete the volume too
docker compose down -v
```

---

## Key Concepts

**Service** — One container (or N replicas of one container). Compose manages each service independently.

**Project** — A whole `docker-compose.yml`. Compose names everything with a project prefix (default: the directory name).
```bash
docker compose -p myapp up -d   # explicit project name
```

**Network** — Compose creates a default network for the project. All services can reach each other by **service name** as a DNS hostname. In the example above, `api` reaches the database at `db:5432` — no IP addresses, no `/etc/hosts`.

**Volume** — Declared at the bottom under `volumes:`. Compose creates a named volume scoped to the project (`myapp_pgdata`).

---

## Useful Commands

```bash
# Start (detached) — builds if there's a `build:` and the image is missing
docker compose up -d

# Force a rebuild
docker compose up -d --build

# Restart just one service
docker compose restart api

# Stop without removing
docker compose stop

# Tail logs from one service
docker compose logs -f api

# Exec into a service
docker compose exec api sh
docker compose exec db psql -U app -d appdb

# Run a one-off command in a fresh container (e.g. migrations)
docker compose run --rm api npm run migrate

# Scale a stateless service to 3 instances
docker compose up -d --scale api=3
# Note: you can't keep `ports:` when scaling — use a load balancer (nginx, traefik) in front

# What did Compose actually compute? (after merging overrides, env vars, etc.)
docker compose config
```

---

## Environment Variables in Compose

Compose reads `.env` from the project directory automatically.

```bash
# .env  (gitignored)
DB_PASSWORD=supersecret
IMAGE_TAG=v1.4.2
```

Reference them in YAML:

```yaml
services:
  api:
    image: myorg/myapi:${IMAGE_TAG:-latest}    # default to 'latest' if unset
    environment:
      DB_PASSWORD: ${DB_PASSWORD:?must be set}  # fail loudly if unset
```

The forms `${VAR:-default}` (use default if unset/empty) and `${VAR:?msg}` (error if unset/empty) are your friends.

---

## depends_on — and Why It's Not Enough

```yaml
api:
  depends_on:
    - db
```

This only waits for the `db` container to **start** — not for Postgres inside it to be **ready** to accept connections. Use a healthcheck and `condition: service_healthy`:

```yaml
api:
  depends_on:
    db:
      condition: service_healthy
```

Combined with the `healthcheck:` block on the `db` service (as in the example above), Compose now waits for Postgres to actually answer queries before starting the API.

---

## Overrides — Dev vs Prod

Compose automatically merges `docker-compose.yml` with `docker-compose.override.yml` if it exists. Use this to keep a base file and a dev-only file.

`docker-compose.yml` (the base — production-like):
```yaml
services:
  api:
    image: myorg/myapi:1.4.2
    restart: unless-stopped
```

`docker-compose.override.yml` (auto-applied in dev):
```yaml
services:
  api:
    build: ./api
    volumes:
      - ./api:/app          # live-reload code
    command: npm run dev
    environment:
      LOG_LEVEL: debug
```

For prod deploys, run with only the base file:
```bash
docker compose -f docker-compose.yml up -d
```

---

## Profiles — Optional Services

```yaml
services:
  api:
    image: myorg/myapi:1.4.2
  db:
    image: postgres:16-alpine
  pgadmin:
    image: dpage/pgadmin4
    profiles: ["debug"]      # only starts when 'debug' profile is active
```

```bash
docker compose up -d                       # starts api + db only
docker compose --profile debug up -d        # starts api + db + pgadmin
```

Useful for tools you only want sometimes (db UIs, mailcatchers, tracing).

---

## Compose vs Kubernetes

Don't get confused: Compose is not a stepping stone you outgrow when you "go to Kubernetes". They solve different problems:

| | Docker Compose | Kubernetes |
|---|----------------|------------|
| Scope | One host | A cluster |
| Complexity | Tiny YAML | Lots of YAML |
| Use for | Dev, small services, CI environments | Multi-host production at scale |

Most teams use **Compose for local dev** and **Kubernetes for prod** — that's a perfectly normal stack.

---

## Key Insight for DevOps

A clean `docker-compose.yml` is the best documentation your project can have. A new engineer should be able to:

```bash
git clone <repo>
cp .env.example .env
docker compose up -d
```

…and have a fully working local environment in under 60 seconds. If your onboarding doc has 30 manual steps, the Compose file is missing services. Move them in.
