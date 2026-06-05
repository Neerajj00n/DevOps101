# Logs & Troubleshooting

Logs are how systems tell you what went wrong. Being fast at reading logs is one of the highest-leverage skills in DevOps — it's the difference between a 5-minute fix and an hour of guessing.

---

## Where Logs Live

```
/var/log/
├── syslog          → general system messages (Debian/Ubuntu)
├── messages        → same (RHEL/CentOS)
├── auth.log        → SSH logins, sudo, authentication
├── kern.log        → kernel messages
├── dmesg           → hardware/boot messages
├── nginx/
│   ├── access.log  → every HTTP request
│   └── error.log   → nginx errors
├── docker/         → container logs (if using json-file driver)
└── apt/            → package manager activity
```

For systemd services, logs go to the **journal** (queried with `journalctl`), not flat files.

---

## Reading Logs

```bash
# Flat files
tail -f /var/log/nginx/error.log          # follow in real time
tail -n 200 /var/log/nginx/access.log     # last 200 lines
grep "ERROR" /var/log/app.log             # filter for errors
grep -i "error\|warn\|fail" /var/log/app.log   # multiple patterns

# journalctl (systemd)
journalctl -u nginx                       # all logs for nginx
journalctl -u nginx -f                    # follow
journalctl -u nginx -n 100               # last 100 lines
journalctl -u nginx --since "2 hours ago"
journalctl -u nginx --since "2024-06-01 10:00" --until "2024-06-01 11:00"
journalctl -p err                         # only error priority and above
journalctl --disk-usage                   # how much space logs are using
journalctl --vacuum-time=7d              # keep only last 7 days

# Kernel/boot messages
dmesg                                     # all kernel messages
dmesg | tail -50                          # recent kernel messages
dmesg -T                                  # with human-readable timestamps
dmesg -l err,warn                         # only errors and warnings
```

---

## Searching & Filtering

```bash
# grep basics
grep "error" app.log                      # case-sensitive
grep -i "error" app.log                   # case-insensitive
grep -v "healthcheck" access.log          # exclude lines matching
grep -n "ERROR" app.log                   # show line numbers
grep -C 5 "OutOfMemory" app.log           # 5 lines context around match
grep -A 3 "FATAL" app.log                 # 3 lines after match
grep -B 3 "FATAL" app.log                 # 3 lines before match

# Multiple files
grep -r "error" /var/log/nginx/           # recursive search
grep -l "error" /var/log/*.log            # just filenames that match

# awk — column-based processing
awk '{print $1, $7}' /var/log/nginx/access.log    # print columns 1 and 7
awk '$9 == "500"' /var/log/nginx/access.log        # lines where col 9 = 500
awk '{print $9}' access.log | sort | uniq -c | sort -rn  # count HTTP status codes

# sed — stream editor
sed 's/127.0.0.1/localhost/g' access.log          # replace text
sed -n '100,200p' app.log                          # print lines 100-200
```

---

## Log Rotation

Logs that aren't rotated fill up disks. Most services configure this automatically via `logrotate`.

```bash
cat /etc/logrotate.conf                    # global config
ls /etc/logrotate.d/                       # per-service configs

# Example logrotate config for your app:
# /var/log/myapp/*.log {
#     daily
#     rotate 14
#     compress
#     delaycompress
#     missingok
#     notifempty
#     create 0640 appuser appuser
# }

logrotate -d /etc/logrotate.d/nginx        # dry run (test config)
logrotate -f /etc/logrotate.d/nginx        # force rotation now
```

---

## Troubleshooting Workflow

When something breaks, work through this in order:

```bash
# 1. Is the service running?
systemctl status myapp

# 2. What did it last say?
journalctl -u myapp -n 50

# 3. Are there disk/memory issues?
df -h
free -h

# 4. Is it listening on the right port?
ss -tlnp | grep :8080

# 5. Can you reach it locally?
curl -v http://localhost:8080/health

# 6. Are there any recent kernel issues?
dmesg -T | tail -20
```

---

## Common Log Patterns & What They Mean

```
# Nginx 502 Bad Gateway
→ app server is down or not responding
→ check: systemctl status myapp; journalctl -u myapp -n 50

# "Too many open files"
→ hit OS file descriptor limit
→ check: ulimit -n; cat /proc/sys/fs/file-max
→ fix: increase limits in /etc/security/limits.conf or systemd unit file

# "Connection refused" in app logs
→ the thing you're trying to connect to (DB, cache, API) isn't listening
→ check: nc -zv hostname port; ss -tlnp on the target

# "OOMKilled" in kernel logs (dmesg)
→ process was killed by OOM killer due to memory pressure
→ check: journalctl -k | grep -i oom; free -h
→ fix: increase memory or tune application memory settings

# "No space left on device"
→ disk is full
→ check: df -h; du -sh /* | sort -rh | head -10
→ common culprits: logs, Docker images, /tmp
```

---

## Key Insight for DevOps

The fastest engineers aren't the ones who know every answer — they're the ones who know how to read logs quickly. Practice `grep -C`, `awk`, and `journalctl` until they're second nature. When you're on a production incident call, every second counts.
