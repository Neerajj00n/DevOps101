# Lab 05 — Shell Scripting

**Goal:** Write real shell scripts that do useful things, not toy exercises.

**Time:** ~45 minutes  
**Prerequisites:** Labs 01–04 completed. A Linux machine.

---

## Tasks

### Part 1 — Basic Script

Write a script called `server-info.sh` that prints:
- Current user and hostname
- Current date and time
- OS name and version (from `/etc/os-release`)
- System uptime
- Number of logged-in users

Run it: `./server-info.sh`

Expected output (example):
```
=== Server Info ===
User     : joon @ web01
Date     : 2024-06-01 10:45:23
OS       : Ubuntu 22.04.3 LTS
Uptime   : up 5 days, 3 hours, 12 minutes
Users    : 2 logged in
```

---

### Part 2 — Script with Arguments

Write a script called `check-port.sh` that:
- Takes a hostname and port as arguments: `./check-port.sh google.com 443`
- Checks if the port is reachable using `nc`
- Prints `[OK] hostname:port is reachable` or `[FAIL] hostname:port is not reachable`
- Exits with code 0 if reachable, 1 if not
- Prints a usage message if called without arguments

---

### Part 3 — Script with a Loop

Write a script called `check-servers.sh` that:
- Reads a list of servers from a file called `servers.txt` (one server per line)
- Pings each server once
- Prints `[UP] servername` or `[DOWN] servername`
- At the end, prints a summary: `X/Y servers are up`

Create a `servers.txt` with at least 3 entries (include one that will definitely fail, like `nonexistent-server-xyz`).

---

### Part 4 — Script with Error Handling

Write a script called `backup.sh` that:
- Takes a source directory as the first argument
- Creates a backup in `/tmp/backups/` with a timestamp in the filename: `backup-YYYY-MM-DD-HHMMSS.tar.gz`
- Uses `set -euo pipefail`
- Validates that the source directory exists before doing anything
- Prints what it's doing at each step
- Prints the size of the resulting backup file

Example: `./backup.sh /etc/nginx`

---

### Part 5 — Challenge

Write a script called `log-report.sh` that:
- Takes a log file path as an argument (default to `/var/log/syslog` if not provided)
- Counts and prints: total lines, error lines, warning lines
- Shows the 5 most recent error lines
- Shows the top 3 most common words in error lines

---

## What Good Scripts Look Like

Your scripts should:
- Start with `#!/bin/bash` and `set -euo pipefail`
- Validate inputs before doing anything
- Print clear messages about what they're doing
- Exit with meaningful codes
- Be readable by someone who didn't write them

---

## Solution

See [solutions/lab-05-solution/](../solutions/lab-05-solution/) after attempting everything.
