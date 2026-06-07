# Lab 01 — Your First Containers

**Goal:** Get fluent with the basic `docker` commands. Pull, run, inspect, log, exec, stop, remove. By the end of this lab the CLI should feel as natural as `ls` and `cd`.

**Time:** ~30 minutes
**Prerequisites:** Docker Engine or Docker Desktop installed. `docker version` should work.

---

## Tasks

### Part 1 — Hello, Containers

1. Run the canonical sanity check. What does the output tell you about the steps Docker took?
   ```bash
   docker run --rm hello-world
   ```

2. Pull (without running) the `nginx:1.27-alpine` image. How big is it? How many layers?
   *(Hint: `docker pull`, then `docker images`, then `docker history`)*

3. Run nginx in the background, name it `web`, and publish container port 80 to host port 8080.

4. Open http://localhost:8080 in a browser (or `curl localhost:8080`). You should see the nginx welcome page.

5. List running containers. Then list **all** containers, including stopped ones.

---

### Part 2 — Inspect & Debug

6. Print the last 20 lines of nginx's logs.

7. Follow the logs in real time. In a second terminal, hit `curl localhost:8080` a few times. Watch the access log lines appear.

8. Show live CPU and memory usage of the `web` container.

9. Use `docker inspect` to find:
   - The container's IP address on the default bridge network.
   - The exact image ID it was created from.
   - The command (entrypoint + cmd) that's running as PID 1 inside it.

10. Get a shell inside the running container. Confirm you're in a minimal Alpine system:
    ```bash
    docker exec -it web sh
    cat /etc/os-release
    ps -ef
    exit
    ```
    How many processes are running inside the container? How does that compare to your host?

---

### Part 3 — Configuration & Lifecycle

11. Stop the `web` container. List all containers — it should still appear, but as `Exited`.

12. Start it again (without re-running). The container resumes with the same filesystem and the same name.

13. Run a second nginx container called `web2` on port `8081`. Both should be reachable simultaneously.

14. Replace the nginx welcome page in `web` with custom content. Use `docker exec` to do it without leaving the host:
    ```bash
    docker exec web sh -c 'echo "<h1>Hello from web</h1>" > /usr/share/nginx/html/index.html'
    curl localhost:8080
    ```

15. Remove `web` (forcefully — it's still running). Then remove `web2` gracefully (stop, then remove).

---

### Part 4 — Environment Variables

16. Run a Postgres container. It needs a password set via env var or it refuses to start:
    ```bash
    docker run -d \
      --name pg \
      -e POSTGRES_PASSWORD=devpass \
      -e POSTGRES_DB=labdb \
      postgres:16-alpine
    ```

17. Connect to it from inside the container using `psql` and run a query:
    ```bash
    docker exec -it pg psql -U postgres -d labdb -c "SELECT version();"
    ```

18. Watch the Postgres logs (`docker logs pg`). You should see the database initialising on first boot.

19. Stop and remove `pg`.

---

### Part 5 — Cleanup

20. Run `docker ps -a`. Are there any stopped containers left? Remove them all in one command.

21. Run `docker images`. Remove the `hello-world` image.

22. Run `docker system df`. How much disk are images, containers, and the build cache using?

23. Reclaim everything that isn't currently in use:
    ```bash
    docker system prune
    ```

---

## Expected Outcomes

By the end of this lab you should be able to, without looking anything up:

- Pull, run, and stop containers
- Map ports, set env vars, name containers
- Read logs, exec into a running container, inspect its metadata
- Tell the difference between a stopped container and a deleted one
- Reclaim disk space when Docker fills your drive

---

## Stretch Goals

- Run `docker run --rm -it alpine sh` and explore. Inside the container, run `ip addr`, `cat /etc/hosts`, `ps -ef`. Compare with your host.
- Run two containers on the **default** bridge network. Try to ping one from the other by name (e.g. `docker exec c1 ping c2`). It will fail. Now create a user-defined bridge network, attach both, and try again. Why does it work the second time?
- Use `--cpus` and `--memory` to limit a container, then stress it with `docker run --rm -it --cpus=0.5 alpine sh -c 'apk add --no-cache stress-ng && stress-ng --cpu 4 --timeout 30s'` and watch `docker stats`. Note the cap.

---

## Solution

Stuck? The point of this lab is repetition — type the commands, get errors, fix them. Every senior engineer has run `docker ps` ten thousand times. There's no shortcut.

If you really need a reference, see [02-containers.md](./02-containers.md) — every command in this lab is in there.
