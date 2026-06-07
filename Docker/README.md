# 04 — Docker & Containers

> Containers changed how software is packaged, shipped, and run. Before Docker, "works on my machine" was a daily problem. Now, the same image runs identically on a laptop, a CI runner, and a production server. Learn Docker properly — every modern DevOps stack assumes you already know it.

---

## 🎯 What You'll Learn

- What containers actually are (and how they differ from VMs)
- Pull, run, inspect, and stop containers from the CLI
- Write Dockerfiles that produce small, secure, reproducible images
- Persist data with volumes and connect containers with networks
- Orchestrate multi-container apps with Docker Compose
- Push images to a registry (Docker Hub / ECR)
- Apply image-hardening and runtime best practices

---

## ✅ Prerequisites

- [Linux](../Linux/) — you must be comfortable in a shell. Containers *are* Linux processes; if `ps`, `ls`, and `cat /etc/os-release` are second nature, you're ready.
- [AWS](../AWS/) — helpful but not required. We will push to ECR in the final lab.

Install Docker Engine (Linux) or Docker Desktop (macOS/Windows) before starting:
- https://docs.docker.com/get-docker/

Verify with:
```bash
docker version
docker run --rm hello-world
```

---

## 📚 Notes

| Topic | File |
|-------|------|
| Images & the Container Model | [01-images.md](./01-images.md) |
| Running Containers | [02-containers.md](./02-containers.md) |
| Writing Dockerfiles | [03-dockerfile.md](./03-dockerfile.md) |
| Volumes & Networks | [04-volumes-networks.md](./04-volumes-networks.md) |
| Docker Compose | [05-compose.md](./05-compose.md) |
| Image Best Practices & Security | [06-best-practices.md](./06-best-practices.md) |

---

## 🧪 Labs

| Lab | Description |
|-----|-------------|
| [Lab 01](./lab-01-first-container.md) | Pull, run, exec, and inspect your first containers |
| [Lab 02](./lab-02-build-image.md) | Write a Dockerfile, build a small image, run it |
| [Lab 03](./lab-03-compose.md) | Run a multi-service app (web + db) with Docker Compose |

---

## 🔧 Module Project

**Containerise the web app you deployed manually in the AWS module.**

By the end you will have:
- A multi-stage Dockerfile producing an image under 150 MB
- A `docker-compose.yml` running the app + a Postgres database + a reverse proxy
- The image pushed to Amazon ECR
- An EC2 instance pulling and running that image on boot via user-data

This is the bridge between "I built infra" (AWS module) and "I run real workloads on it" (every module after this).

---

## ➡️ Next Module

05 — Kubernetes → *(coming soon)*
