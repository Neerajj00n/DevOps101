# Lab 03 — Multi-Service App with Docker Compose

**Goal:** Stand up a real two-tier application (Flask API + Postgres) using Docker Compose. Add a healthcheck-gated dependency, a persistent volume, environment-based config, and a one-off migration job. By the end, `docker compose up -d` should bring the whole thing up clean every time.

**Time:** ~45 minutes
**Prerequisites:** Labs 01 and 02 completed. `docker compose version` should work (Compose v2 is bundled with modern Docker).

---

## Setup

```bash
mkdir -p ~/devops-lab/docker-lab-03/api
cd ~/devops-lab/docker-lab-03
```

Create the API. It connects to Postgres, creates a `visits` table on startup, and increments a counter on every request.

```bash
cat > api/app.py <<'EOF'
import os, time
import psycopg
from flask import Flask, jsonify

DB_URL = os.environ["DATABASE_URL"]

def connect_with_retry(retries=10, delay=2):
    last = None
    for _ in range(retries):
        try:
            return psycopg.connect(DB_URL, autocommit=True)
        except Exception as e:
            last = e
            time.sleep(delay)
    raise last

def init_db():
    with connect_with_retry() as conn, conn.cursor() as cur:
        cur.execute("""
            CREATE TABLE IF NOT EXISTS visits (
                id SERIAL PRIMARY KEY,
                ts TIMESTAMPTZ DEFAULT NOW()
            )
        """)

app = Flask(__name__)
init_db()

@app.get("/")
def index():
    with connect_with_retry() as conn, conn.cursor() as cur:
        cur.execute("INSERT INTO visits DEFAULT VALUES")
        cur.execute("SELECT COUNT(*) FROM visits")
        count = cur.fetchone()[0]
    return jsonify(visits=count, host=os.uname().nodename)

@app.get("/health")
def health():
    return {"status": "ok"}, 200
EOF

cat > api/requirements.txt <<'EOF'
flask==3.0.3
gunicorn==22.0.0
psycopg[binary]==3.2.1
EOF

cat > api/Dockerfile <<'EOF'
# syntax=docker/dockerfile:1.7
FROM python:3.12-slim
WORKDIR /app

COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

RUN useradd --system --create-home --uid 1000 app
USER app

COPY --chown=app:app app.py .

EXPOSE 8080
CMD ["gunicorn", "--bind", "0.0.0.0:8080", "--workers", "2", "app:app"]
EOF
```

---

## Tasks

### Part 1 — A Minimal Compose File

1. Create `docker-compose.yml` at the project root:

   ```yaml
   services:
     db:
       image: postgres:16-alpine
       restart: unless-stopped
       environment:
         POSTGRES_USER: app
         POSTGRES_PASSWORD: ${DB_PASSWORD:?DB_PASSWORD must be set}
         POSTGRES_DB: appdb
       volumes:
         - pgdata:/var/lib/postgresql/data
       healthcheck:
         test: ["CMD-SHELL", "pg_isready -U app -d appdb"]
         interval: 5s
         timeout: 3s
         retries: 5

     api:
       build: ./api
       image: lab03/api:dev
       restart: unless-stopped
       environment:
         DATABASE_URL: postgres://app:${DB_PASSWORD}@db:5432/appdb
       ports:
         - "127.0.0.1:8080:8080"
       depends_on:
         db:
           condition: service_healthy

   volumes:
     pgdata:
   ```

2. Create `.env` (and add it to a `.gitignore` if you're using git):
   ```bash
   echo 'DB_PASSWORD=devsecret' > .env
   echo '.env' >> .gitignore
   ```

3. Bring it up:
   ```bash
   docker compose up -d --build
   docker compose ps
   ```
   Both services should be `running`. The `db` should report `healthy` after a few seconds.

4. Hit the API:
   ```bash
   curl localhost:8080
   curl localhost:8080
   curl localhost:8080
   ```
   The `visits` count should increment on each call.

---

### Part 2 — Service Discovery

5. Notice that the API connects to `db:5432`, not an IP. Confirm that this DNS works inside the project network:
   ```bash
   docker compose exec api python -c "import socket; print(socket.gethostbyname('db'))"
   ```

6. Now try the same lookup from a container *outside* the project:
   ```bash
   docker run --rm alpine getent hosts db
   ```
   It fails — `db` only resolves inside the Compose-created network.

7. List the network Compose created:
   ```bash
   docker network ls | grep $(basename $(pwd))
   docker network inspect $(basename $(pwd))_default
   ```

---

### Part 3 — Persistence

8. Verify the data survives container restarts. Note the current visit count.
   ```bash
   curl localhost:8080
   ```

9. Recreate just the API:
   ```bash
   docker compose up -d --force-recreate api
   curl localhost:8080
   ```
   The count keeps climbing — the data lives in Postgres, which wasn't recreated.

10. Recreate the database container too (but keep the volume):
    ```bash
    docker compose up -d --force-recreate db
    sleep 5
    curl localhost:8080
    ```
    Count still increments — the named volume `pgdata` outlived the container.

11. Now nuke the volume and observe the difference:
    ```bash
    docker compose down -v       # -v wipes volumes
    docker compose up -d --build
    sleep 8
    curl localhost:8080
    ```
    The count starts back at 1. Volumes are how state survives.

---

### Part 4 — Logs, Exec, One-off Commands

12. Tail logs for just the API service:
    ```bash
    docker compose logs -f api
    ```

13. Open a `psql` prompt inside the database container:
    ```bash
    docker compose exec db psql -U app -d appdb -c "SELECT COUNT(*) FROM visits;"
    ```

14. Run a one-off Python command in a *fresh* api container (does not interfere with the running one):
    ```bash
    docker compose run --rm api python -c "import flask; print(flask.__version__)"
    ```

---

### Part 5 — Dev Override (Live Reload)

15. Right now, changing `api/app.py` requires `docker compose build && docker compose up -d`. For local dev, mount the code in. Create `docker-compose.override.yml`:

    ```yaml
    services:
      api:
        volumes:
          - ./api:/app
        command: ["python", "-c", "from app import app; app.run(host='0.0.0.0', port=8080, debug=True)"]
    ```

    Compose merges this on top of the base file automatically.

16. Recreate the api service:
    ```bash
    docker compose up -d api
    ```

17. Edit `api/app.py` — change the JSON to include `"version": "1.0"`. Save the file. Hit the endpoint again. The Flask debug server reloads the code without rebuilding the image.

18. For a "production-like" run that ignores the override, use:
    ```bash
    docker compose -f docker-compose.yml up -d
    ```

---

### Part 6 — Adding a Reverse Proxy (Stretch)

19. Add an `nginx` service in front of the API so the API doesn't expose its port to the host:

    ```yaml
    # add to docker-compose.yml
    services:
      proxy:
        image: nginx:1.27-alpine
        ports:
          - "8080:80"
        volumes:
          - ./nginx.conf:/etc/nginx/conf.d/default.conf:ro
        depends_on:
          - api
    ```

    And remove the `ports:` block from `api` (only `proxy` should be reachable from the host).

20. Create `nginx.conf`:
    ```nginx
    server {
        listen 80;
        location / {
            proxy_pass http://api:8080;
            proxy_set_header Host $host;
            proxy_set_header X-Real-IP $remote_addr;
        }
    }
    ```

21. `docker compose up -d`. Verify the API is no longer directly reachable from the host, but the proxy works:
    ```bash
    curl localhost:8080         # via nginx → api → db
    docker compose exec proxy curl -s api:8080   # works (internal network)
    ```

This is the production pattern in miniature: only the proxy is exposed; the app and database are reachable only on the internal network.

---

### Part 7 — Cleanup

22. Tear down everything, including volumes and the built image:
    ```bash
    docker compose down -v --rmi local
    ```

23. Confirm:
    ```bash
    docker compose ps
    docker volume ls | grep pgdata
    docker images | grep lab03
    ```

---

## Expected Outcomes

- A real multi-service app brought up with a single command
- Confidence with healthcheck-based `depends_on`
- A working mental model of Compose networks (DNS scoping by project)
- An understanding of how to layer dev overrides on top of a production-like base
- The recognition that "Compose vs Kubernetes" is a *scale* decision, not a *seriousness* decision

---

## Connecting to the Rest of the Course

You've now built infrastructure (AWS module), automated it (Terraform module), and packaged a workload to run on it (this module). The natural next step is putting them together:

- Push this image to **ECR** (covered briefly in [06-best-practices.md](./06-best-practices.md))
- Provision an **EC2 instance** with Terraform and have its `user_data` pull and run the image
- Or skip ahead to **Kubernetes**, where this same Compose file becomes a couple of Deployment + Service manifests

Each module reinforces the last. That's the point.

---

## Solution

The reference docker-compose.yml is the one in [05-compose.md](./05-compose.md). If your stack comes up cleanly with `docker compose up -d` from a fresh clone, you're done — there's no single "correct" version.
