# Lab 02 — Build Your First Image

**Goal:** Write a Dockerfile from scratch, build a small image, and learn how layer caching, multi-stage builds, and `.dockerignore` make your images fast and small.

**Time:** ~45 minutes
**Prerequisites:** Lab 01 completed. Python 3 installed locally is helpful but not required.

---

## Setup

Create a working directory:

```bash
mkdir -p ~/devops-lab/docker-lab-02
cd ~/devops-lab/docker-lab-02
```

Create a tiny Flask app:

```bash
cat > app.py <<'EOF'
import os
from flask import Flask

app = Flask(__name__)

@app.get("/")
def index():
    return f"Hello from {os.uname().nodename}\n"

@app.get("/health")
def health():
    return {"status": "ok"}, 200

if __name__ == "__main__":
    app.run(host="0.0.0.0", port=8080)
EOF

cat > requirements.txt <<'EOF'
flask==3.0.3
gunicorn==22.0.0
EOF
```

---

## Tasks

### Part 1 — A Naive Dockerfile

1. Create a Dockerfile that:
   - Starts from `python:3.12`
   - Sets `/app` as the working directory
   - Copies *everything* into the image
   - Installs requirements
   - Runs the app with `python app.py`

   Build it: `docker build -t flaskapp:v1 .`

2. Run it: `docker run --rm -p 8080:8080 flaskapp:v1`. Test with `curl localhost:8080`.

3. Check the image size: `docker images flaskapp`. How big is it?

4. Now make a trivial change to `app.py` (e.g. change "Hello" to "Hi"). Rebuild. **Watch carefully** — does Docker re-run `pip install`? Why?

---

### Part 2 — Order Layers for Caching

5. Rewrite the Dockerfile so dependencies are installed *before* the source code is copied. The layer order should be:
   ```
   FROM
   WORKDIR
   COPY requirements.txt .
   RUN pip install ...
   COPY . .
   CMD ...
   ```

6. Rebuild from scratch: `docker build --no-cache -t flaskapp:v2 .`

7. Now change `app.py` again and rebuild **without** `--no-cache`. The build should be near-instant — `pip install` is cached. Confirm with the build output: you should see `CACHED` next to the install step.

---

### Part 3 — Slim It Down

8. Switch the base from `python:3.12` to `python:3.12-slim`. Add `--no-cache-dir` to the pip install. Rebuild as `flaskapp:v3`.

9. Compare sizes:
   ```bash
   docker images | grep flaskapp
   ```
   `v3` should be roughly **5×** smaller than `v1`.

10. Add a `.dockerignore` file:
    ```
    __pycache__
    *.pyc
    .git
    .env
    *.md
    Dockerfile*
    ```
    Rebuild and verify the build context size in the output line `Sending build context to Docker daemon, ... B`. Without `.dockerignore`, even a `.git` directory gets shipped to the daemon every build.

---

### Part 4 — Run as Non-Root

11. The container is currently running as `root` (verify: `docker run --rm flaskapp:v3 id`).

12. Add a non-root user to the Dockerfile. After the `COPY . .`:
    ```dockerfile
    RUN useradd --system --create-home --uid 1000 app && chown -R app:app /app
    USER app
    ```
    Rebuild as `flaskapp:v4`. Verify `docker run --rm flaskapp:v4 id` shows `uid=1000(app)`.

13. Confirm the app still works.

---

### Part 5 — Multi-Stage & gunicorn

The single-process Flask dev server is fine for this lab, but a real production image would use `gunicorn` and ideally not even include the Python toolchain at runtime. Try a multi-stage build.

14. Create `Dockerfile.multi`:

    ```dockerfile
    # syntax=docker/dockerfile:1.7

    # ── builder ────────────────────────────────────────
    FROM python:3.12-slim AS builder
    WORKDIR /build

    COPY requirements.txt .
    RUN pip install --no-cache-dir --prefix=/install -r requirements.txt

    # ── runtime ────────────────────────────────────────
    FROM python:3.12-slim
    WORKDIR /app

    # bring in the pre-installed deps from the builder
    COPY --from=builder /install /usr/local

    # non-root user
    RUN useradd --system --create-home --uid 1000 app
    USER app

    COPY --chown=app:app app.py .

    EXPOSE 8080
    HEALTHCHECK --interval=30s --timeout=3s CMD \
      python -c "import urllib.request,sys; sys.exit(0 if urllib.request.urlopen('http://127.0.0.1:8080/health').status==200 else 1)"

    CMD ["gunicorn", "--bind", "0.0.0.0:8080", "--workers", "2", "app:app"]
    ```

15. Build and run:
    ```bash
    docker build -f Dockerfile.multi -t flaskapp:v5 .
    docker run -d --name flask -p 8080:8080 flaskapp:v5
    curl localhost:8080
    curl localhost:8080/health
    ```

16. Wait ~30 seconds, then `docker ps`. The `STATUS` column should show `(healthy)`. The healthcheck is doing its job.

17. Compare sizes one more time:
    ```bash
    docker images | grep flaskapp
    ```
    Note that the multi-stage build isn't dramatically smaller here (the deps are the same), but the *pattern* shines for compiled languages — try the same exercise with a Go or Rust app and the difference is 50–100×.

---

### Part 6 — Tagging & Inspection

18. Re-tag your final image with a moving tag and a version tag:
    ```bash
    docker tag flaskapp:v5 flaskapp:1.0.0
    docker tag flaskapp:v5 flaskapp:latest
    docker images | grep flaskapp
    ```

19. Inspect the layers of the final image:
    ```bash
    docker history flaskapp:1.0.0
    ```
    Each line is a layer. Identify which layer added your source code, which added Python deps, and which added the user.

20. Cleanup:
    ```bash
    docker rm -f flask
    docker rmi flaskapp:v1 flaskapp:v2 flaskapp:v3 flaskapp:v4 flaskapp:v5 flaskapp:1.0.0 flaskapp:latest
    ```

---

## Expected Outcomes

- A working Dockerfile that builds a < 200 MB image of a Python web app
- An understanding of *why* the order of `COPY` and `RUN` matters
- Hands-on experience with `.dockerignore`, non-root users, multi-stage builds, and healthchecks
- The intuition to look at any Dockerfile and say "that's going to be a 1.5 GB image" before building it

---

## Stretch Goals

- Add a build arg `APP_VERSION` and bake it into a `LABEL`. Build with `--build-arg APP_VERSION=1.0.0` and confirm with `docker inspect`.
- Run `trivy image flaskapp:1.0.0` (install Trivy first). How many CVEs does it find? Are they in your code or in the base image?
- Build a `gcr.io/distroless/python3-debian12` version. It will fight you (no shell, no pip at runtime). The point is to feel why distroless is more secure — and more fiddly.

---

## Solution

This lab has many small steps but no single right answer — your final Dockerfile may differ from a colleague's and both can be correct. The reference Dockerfile in [03-dockerfile.md](./03-dockerfile.md) (the multi-stage Python example pattern) is a fine target.
