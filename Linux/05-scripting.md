# Shell Scripting

Shell scripts let you automate anything you can do in a terminal. In DevOps you'll write scripts for deployments, health checks, cleanup jobs, and anything that needs to run on a schedule. This is the minimum you need to write useful, readable scripts.

---

## Script Basics

```bash
#!/bin/bash
# Always start with a shebang — tells the OS which interpreter to use

# Make it executable
chmod +x myscript.sh

# Run it
./myscript.sh
bash myscript.sh      # alternative, doesn't need executable bit
```

---

## Variables

```bash
#!/bin/bash

NAME="joon"
PORT=8080

echo "Hello, $NAME"
echo "Running on port: ${PORT}"   # braces for clarity when concatenating

# Command substitution — store command output in a variable
CURRENT_DATE=$(date +%Y-%m-%d)
DISK_USAGE=$(df -h / | awk 'NR==2 {print $5}')

echo "Date: $CURRENT_DATE"
echo "Disk used: $DISK_USAGE"

# Environment variables
echo "Home dir: $HOME"
echo "Current user: $USER"
echo "Script name: $0"
echo "First argument: $1"
echo "All arguments: $@"
echo "Argument count: $#"
```

---

## Conditionals

```bash
#!/bin/bash

STATUS=$(systemctl is-active nginx)

if [ "$STATUS" = "active" ]; then
    echo "nginx is running"
elif [ "$STATUS" = "inactive" ]; then
    echo "nginx is stopped"
else
    echo "nginx status unknown: $STATUS"
fi

# Common test operators
[ -f /etc/nginx/nginx.conf ]    # file exists
[ -d /var/log/nginx ]           # directory exists
[ -z "$VAR" ]                   # string is empty
[ -n "$VAR" ]                   # string is not empty
[ "$A" = "$B" ]                 # strings are equal
[ $NUM -gt 10 ]                 # number greater than
[ $NUM -le 100 ]                # number less than or equal

# Combine conditions
if [ -f /tmp/lock ] && [ -n "$USER" ]; then
    echo "lock exists and user is set"
fi
```

---

## Loops

```bash
#!/bin/bash

# For loop — iterate over a list
for SERVER in web01 web02 web03; do
    echo "Checking $SERVER..."
    ping -c 1 "$SERVER" &>/dev/null && echo "  UP" || echo "  DOWN"
done

# For loop — over numbers
for i in $(seq 1 5); do
    echo "Attempt $i"
done

# While loop
RETRIES=0
while [ $RETRIES -lt 5 ]; do
    curl -s https://myapp.com/health && break
    RETRIES=$((RETRIES + 1))
    echo "Attempt $RETRIES failed, retrying..."
    sleep 5
done

# Loop over files
for FILE in /var/log/*.log; do
    echo "Processing: $FILE"
done
```

---

## Functions

```bash
#!/bin/bash

# Define a function
log() {
    echo "[$(date +%H:%M:%S)] $1"
}

check_service() {
    local SERVICE=$1    # local = scoped to this function
    if systemctl is-active --quiet "$SERVICE"; then
        log "$SERVICE is running"
        return 0
    else
        log "$SERVICE is NOT running"
        return 1
    fi
}

# Call it
check_service nginx
check_service docker
```

---

## Exit Codes & Error Handling

```bash
#!/bin/bash

# Every command returns an exit code: 0 = success, non-zero = failure
ls /nonexistent
echo "Exit code: $?"    # $? holds last exit code

# Exit immediately on error (recommended for scripts)
set -e

# Exit on undefined variable
set -u

# Both together (best practice)
set -euo pipefail
# pipefail: if any command in a pipe fails, the whole pipe fails

# Trap — run cleanup on exit or error
cleanup() {
    echo "Cleaning up..."
    rm -f /tmp/myapp.lock
}
trap cleanup EXIT        # run on any exit
trap cleanup ERR         # run on error

# Manual exit with code
exit 0    # success
exit 1    # generic failure
```

---

## Practical Patterns

```bash
#!/bin/bash
set -euo pipefail

# Check dependencies before running
command -v docker &>/dev/null || { echo "docker not found"; exit 1; }
command -v kubectl &>/dev/null || { echo "kubectl not found"; exit 1; }

# Read input with a default value
ENVIRONMENT=${1:-"staging"}
echo "Deploying to: $ENVIRONMENT"

# Redirect output to log file
exec > >(tee -a /var/log/deploy.log) 2>&1

# Check if running as root
if [ "$EUID" -ne 0 ]; then
    echo "This script must be run as root"
    exit 1
fi

# Wait for a service to be ready
wait_for_port() {
    local HOST=$1
    local PORT=$2
    local TIMEOUT=${3:-30}
    local COUNT=0
    
    echo "Waiting for $HOST:$PORT..."
    while ! nc -zv "$HOST" "$PORT" &>/dev/null; do
        COUNT=$((COUNT + 1))
        [ $COUNT -ge $TIMEOUT ] && { echo "Timeout waiting for $HOST:$PORT"; exit 1; }
        sleep 1
    done
    echo "$HOST:$PORT is ready"
}
```

---

## Key Insight for DevOps

The best scripts are **boring** — they log what they're doing, fail loudly with a clear message, and clean up after themselves. A script that silently does the wrong thing is worse than one that crashes immediately.

Always use `set -euo pipefail`. Always log. Always add a cleanup trap.
