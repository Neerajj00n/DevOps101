# Networking Basics

You don't need to be a network engineer, but you need to know enough to debug connectivity issues on a server. This covers the tools you'll actually use in production.

---

## Network Interfaces

```bash
ip addr                       # all interfaces + IP addresses
ip addr show eth0             # specific interface
ip link                       # interface up/down status
ifconfig                      # older alternative (may not be installed)

# Output explained:
# 2: eth0: <BROADCAST,MULTICAST,UP,LOWER_UP>
#     inet 10.0.1.50/24 brd 10.0.1.255 scope global eth0
# inet = IPv4 address, /24 = subnet mask (255.255.255.0)
```

---

## Routing

```bash
ip route                      # routing table
ip route show default         # default gateway (where traffic goes if no specific route)

# You'll see something like:
# default via 10.0.1.1 dev eth0
# 10.0.1.0/24 dev eth0 proto kernel scope link src 10.0.1.50
```

---

## DNS

```bash
cat /etc/resolv.conf          # configured DNS servers
cat /etc/hosts                # local hostname overrides (checked before DNS)

nslookup google.com           # DNS lookup
dig google.com                # detailed DNS lookup
dig google.com A              # IPv4 records only
dig @8.8.8.8 google.com       # query specific DNS server

# Debug: can the server resolve names?
dig google.com +short
```

---

## Connectivity Testing

```bash
ping 8.8.8.8                  # basic ICMP connectivity (Ctrl+C to stop)
ping -c 4 google.com          # send 4 pings then stop

traceroute google.com         # trace the route packets take
mtr google.com                # combined ping + traceroute (live)

# Test if a port is reachable
telnet 10.0.1.50 80           # old school (ctrl+] then quit)
nc -zv 10.0.1.50 80           # netcat: -z = scan, -v = verbose
curl -I https://example.com   # HTTP check with headers

# Test from a specific interface
ping -I eth1 8.8.8.8
```

---

## Open Ports

```bash
ss -tlnp                      # TCP listening ports + process
ss -ulnp                      # UDP listening ports
ss -tlnp | grep :443          # is something on 443?

# What process owns a port?
lsof -i :80
lsof -i :8080 -i :443         # check multiple ports

# Full connection state view
ss -tnp state established     # active TCP connections
```

---

## Firewall (UFW / iptables)

```bash
# UFW (Ubuntu's simplified firewall)
sudo ufw status               # is firewall on? what rules?
sudo ufw enable
sudo ufw allow 22             # allow SSH
sudo ufw allow 80/tcp
sudo ufw deny 3306            # block MySQL from outside
sudo ufw delete allow 80      # remove a rule

# iptables (lower level, all distros)
sudo iptables -L -n -v        # list all rules
sudo iptables -L INPUT -n     # just incoming rules
```

---

## curl — The DevOps Swiss Army Knife

```bash
curl https://api.example.com                          # GET request
curl -X POST https://api.example.com/data \
     -H "Content-Type: application/json" \
     -d '{"key": "value"}'                            # POST with JSON

curl -I https://example.com                           # headers only
curl -L https://example.com                           # follow redirects
curl -o /tmp/file.tar.gz https://example.com/file     # download to file
curl -v https://example.com                           # verbose (great for debugging)
curl --resolve myapp.local:443:10.0.1.50 https://myapp.local   # test with custom DNS
```

---

## SSH

```bash
ssh user@server                         # basic connect
ssh -i ~/.ssh/mykey.pem user@server     # with specific key
ssh -p 2222 user@server                 # custom port
ssh -L 8080:localhost:80 user@server    # local port forward (tunnel)
ssh -J bastion user@private-server      # jump through bastion host

# Config file (~/.ssh/config)
Host myserver
    HostName 10.0.1.50
    User ubuntu
    IdentityFile ~/.ssh/mykey.pem
    Port 22

# Then just: ssh myserver
```

---

## Key Insight for DevOps

The most common connectivity questions you'll debug:
1. **"My app can't reach the database"** → `nc -zv db-host 5432` first. Is the port even reachable? If not, it's a security group / firewall issue, not an app config issue.
2. **"DNS isn't resolving"** → `dig` + check `/etc/resolv.conf`. In Kubernetes this is usually a CoreDNS issue.
3. **"Port is already in use"** → `ss -tlnp | grep :PORT` to find what's holding it.

Ping is often blocked in cloud environments. If ping fails, try `curl` or `nc` before assuming connectivity is broken.
