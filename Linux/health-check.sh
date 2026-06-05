#!/bin/bash
# health-check.sh — System Health Report
# Module 01 Project Solution

set -euo pipefail

# ─────────────────────────────────────────
# Colors
# ─────────────────────────────────────────
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color
BOLD='\033[1m'

# ─────────────────────────────────────────
# Helper functions
# ─────────────────────────────────────────
header() {
    echo ""
    echo -e "${BOLD}${BLUE}══════════════════════════════════════${NC}"
    echo -e "${BOLD}${BLUE}  $1${NC}"
    echo -e "${BOLD}${BLUE}══════════════════════════════════════${NC}"
}

ok()   { echo -e "  ${GREEN}✓${NC} $1"; }
warn() { echo -e "  ${YELLOW}⚠${NC} $1"; }
fail() { echo -e "  ${RED}✗${NC} $1"; }

# ─────────────────────────────────────────
# 1. CPU & Memory Usage
# ─────────────────────────────────────────
header "CPU & Memory"

CPU_CORES=$(nproc)
CPU_IDLE=$(top -bn1 | grep "Cpu(s)" | awk '{print $8}' | cut -d. -f1)
CPU_USED=$((100 - CPU_IDLE))

MEM_TOTAL=$(free -m | awk 'NR==2{print $2}')
MEM_USED=$(free -m | awk 'NR==2{print $3}')
MEM_FREE=$(free -m | awk 'NR==2{print $4}')
MEM_PCT=$(( MEM_USED * 100 / MEM_TOTAL ))

echo "  CPU Cores   : $CPU_CORES"
echo "  CPU Used    : ${CPU_USED}%"

if [ "$MEM_PCT" -lt 70 ]; then
    ok "Memory: ${MEM_USED}MB / ${MEM_TOTAL}MB (${MEM_PCT}%)"
elif [ "$MEM_PCT" -lt 90 ]; then
    warn "Memory: ${MEM_USED}MB / ${MEM_TOTAL}MB (${MEM_PCT}%) — getting high"
else
    fail "Memory: ${MEM_USED}MB / ${MEM_TOTAL}MB (${MEM_PCT}%) — critical!"
fi

# ─────────────────────────────────────────
# 2. Top 5 Processes by Memory
# ─────────────────────────────────────────
header "Top 5 Processes by Memory"

echo "  %-8s %-8s %-6s %-6s %s" "PID" "USER" "%CPU" "%MEM" "COMMAND" | xargs printf "  %-8s %-8s %-6s %-6s %s\n"
echo "  ────────────────────────────────────────────"
ps aux --sort=-%mem | awk 'NR>1 && NR<=6 {printf "  %-8s %-8s %-6s %-6s %s\n", $2, $1, $3, $4, $11}'

# ─────────────────────────────────────────
# 3. Disk Usage
# ─────────────────────────────────────────
header "Disk Usage"

df -h | grep -E '^/dev/' | while read -r line; do
    PARTITION=$(echo "$line" | awk '{print $1}')
    SIZE=$(echo "$line" | awk '{print $2}')
    USED=$(echo "$line" | awk '{print $3}')
    PCT=$(echo "$line" | awk '{print $5}' | tr -d '%')
    MOUNT=$(echo "$line" | awk '{print $6}')

    if [ "$PCT" -lt 70 ]; then
        ok "$MOUNT ($PARTITION): ${USED} / ${SIZE} (${PCT}%)"
    elif [ "$PCT" -lt 90 ]; then
        warn "$MOUNT ($PARTITION): ${USED} / ${SIZE} (${PCT}%) — getting full"
    else
        fail "$MOUNT ($PARTITION): ${USED} / ${SIZE} (${PCT}%) — critical!"
    fi
done

# ─────────────────────────────────────────
# 4. Network Interfaces
# ─────────────────────────────────────────
header "Network Interfaces"

ip -br addr | while read -r line; do
    IFACE=$(echo "$line" | awk '{print $1}')
    STATE=$(echo "$line" | awk '{print $2}')
    ADDR=$(echo "$line" | awk '{print $3}')

    if [ "$STATE" = "UP" ]; then
        ok "$IFACE — UP — ${ADDR:-no IP}"
    elif [ "$IFACE" = "lo" ]; then
        echo "    $IFACE — loopback"
    else
        warn "$IFACE — $STATE"
    fi
done

# ─────────────────────────────────────────
# 5. Recent Syslog Entries
# ─────────────────────────────────────────
header "Last 10 Syslog Entries"

LOG_FILE=""
if [ -f /var/log/syslog ]; then
    LOG_FILE="/var/log/syslog"
elif [ -f /var/log/messages ]; then
    LOG_FILE="/var/log/messages"
fi

if [ -n "$LOG_FILE" ]; then
    tail -n 10 "$LOG_FILE" | while read -r line; do
        echo "  $line"
    done
else
    echo "  No syslog file found — trying journalctl..."
    journalctl -n 10 --no-pager 2>/dev/null || echo "  journalctl not available"
fi

# ─────────────────────────────────────────
# Summary
# ─────────────────────────────────────────
header "Summary"
echo "  Host     : $(hostname)"
echo "  Uptime   : $(uptime -p)"
echo "  Load avg : $(uptime | awk -F'load average:' '{print $2}')"
echo "  Report   : $(date '+%Y-%m-%d %H:%M:%S')"
echo ""
