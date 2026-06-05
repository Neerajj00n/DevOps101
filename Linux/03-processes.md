# Processes & System Info

A process is any running program. In DevOps you'll constantly check what's running, why something is eating CPU, or why a port is already in use. This is how you do it.

---

## Viewing Processes

```bash
ps aux                        # all running processes, detailed
ps aux | grep nginx           # find a specific process
ps -ef --forest               # tree view showing parent-child relationships

top                           # live updating view (q to quit)
htop                          # better top — may need: sudo apt install htop
```

**ps aux output columns:**
```
USER   PID  %CPU %MEM    VSZ   RSS  STAT  COMMAND
root   1234  0.0  0.1  12345  1024  Ss    nginx: master
```

- **PID** — process ID (every process has a unique one)
- **PPID** — parent process ID
- **%CPU / %MEM** — resource usage
- **STAT** — S=sleeping, R=running, Z=zombie, D=uninterruptible sleep

---

## Signals — Talking to Processes

```bash
kill PID                      # send SIGTERM (polite: "please stop")
kill -9 PID                   # send SIGKILL (force kill, no cleanup)
kill -HUP PID                 # reload config without restart (nginx, etc.)
pkill nginx                   # kill by name
killall nginx                 # kill all processes with that name

# When to use -9:
# Only when process ignores normal kill. It skips cleanup, so use as last resort.
```

---

## System Resource Usage

```bash
free -h                       # memory usage (human readable)
df -h                         # disk space per filesystem
df -ih                        # inode usage (can run out even with disk space left)
du -sh /var/log/              # how much space a directory uses
du -sh /* | sort -rh | head   # what's taking up the most space

uptime                        # how long system's been running + load averages
# Load average: 1min, 5min, 15min — rule of thumb: stay under # of CPU cores
nproc                         # number of CPU cores
lscpu                         # detailed CPU info
```

---

## Ports & Network Processes

```bash
# What's listening on which port?
ss -tlnp                      # modern (recommended)
netstat -tlnp                 # older, same idea

# Is something on port 80?
ss -tlnp | grep :80
lsof -i :80                   # list open files for port 80 (includes PID)

# Kill whatever is on port 8080
kill $(lsof -t -i:8080)
```

---

## systemd — Service Management

Most Linux servers use systemd to manage services (nginx, docker, kubelet, etc.)

```bash
systemctl status nginx              # is it running? recent logs?
systemctl start nginx               # start it
systemctl stop nginx                # stop it
systemctl restart nginx             # stop + start
systemctl reload nginx              # reload config without downtime
systemctl enable nginx              # start automatically on boot
systemctl disable nginx             # don't start on boot

systemctl list-units --type=service        # all services
systemctl list-units --type=service --state=failed   # what's broken?

# Check logs for a service
journalctl -u nginx                         # all logs for nginx
journalctl -u nginx -f                      # follow in real time
journalctl -u nginx --since "1 hour ago"    # last hour only
journalctl -u nginx -n 100                  # last 100 lines
```

---

## Background Jobs

```bash
command &                     # run in background
jobs                          # list background jobs
fg                            # bring last background job to foreground
fg %2                         # bring job #2 to foreground
bg                            # resume stopped job in background
Ctrl+Z                        # pause (suspend) a running process

# For long-running tasks that should survive SSH disconnect:
nohup ./long-script.sh &      # immune to hangup signal
screen                        # full terminal multiplexer
tmux                          # better screen (highly recommended for prod work)
```

---

## Key Insight for DevOps

When something is wrong on a server, your investigation order is usually:
1. `systemctl status <service>` — is the service even running?
2. `journalctl -u <service> -n 100` — what did it last say?
3. `ps aux | grep <process>` — is the process actually there?
4. `ss -tlnp` — is it listening on the expected port?
5. `free -h` and `df -h` — is it an OOM or disk-full situation?

This sequence resolves the majority of production incidents.
