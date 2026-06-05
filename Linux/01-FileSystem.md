# Filesystem & Navigation

The Linux filesystem is a tree. Everything starts at `/` (root) and branches from there. There are no drive letters like Windows — everything is a path.

---

## The Filesystem Hierarchy

```
/
├── bin/        → essential binaries (ls, cp, mv, bash)
├── etc/        → system configuration files
├── home/       → user home directories (/home/joon)
├── var/        → variable data — logs, caches, spool files
├── tmp/        → temporary files (cleared on reboot)
├── usr/        → user programs and libraries
├── opt/        → optional third-party software
├── proc/       → virtual filesystem for process/kernel info
├── sys/        → virtual filesystem for hardware/kernel state
├── dev/        → device files (disks, terminals, etc.)
└── root/       → root user's home directory
```

The ones you'll touch most in DevOps: `/etc`, `/var/log`, `/home`, `/tmp`, `/proc`.

---

## Essential Navigation Commands

```bash
pwd                  # where am I right now?
ls                   # list files in current directory
ls -la               # list all files including hidden, with details
cd /etc              # change to absolute path
cd ..                # go up one level
cd ~                 # go to your home directory
cd -                 # go back to previous directory

# -la output explained:
# drwxr-xr-x  2 joon joon 4096 Jun  1 10:00 myfolder
# [type+perms] [links] [owner] [group] [size] [date] [name]
```

---

## Absolute vs Relative Paths

```bash
# Absolute — always starts from root /
cd /etc/nginx/conf.d

# Relative — starts from where you are now
cd ../conf.d          # up one, then into conf.d
cd ./scripts          # into scripts inside current dir
```

---

## Finding Files

```bash
find / -name "nginx.conf"           # find by name, search from root
find /etc -name "*.conf"            # all .conf files under /etc
find /var/log -mtime -1             # modified in last 24 hours
find /home -type f -size +100M      # files over 100MB

which nginx                         # location of a binary
whereis nginx                       # binary + man page + source locations
locate nginx.conf                   # fast search (uses index, run updatedb first)
```

---

## Viewing File Contents

```bash
cat /etc/os-release                 # print entire file
less /var/log/syslog                # paginated view (q to quit, / to search)
head -n 20 /var/log/syslog          # first 20 lines
tail -n 50 /var/log/syslog          # last 50 lines
tail -f /var/log/syslog             # follow in real time (great for logs)
grep "error" /var/log/syslog        # search inside file
```

---

## Copying, Moving, Deleting

```bash
cp file.txt /tmp/                   # copy file to /tmp
cp -r mydir/ /tmp/                  # copy directory recursively
mv file.txt newname.txt             # rename or move
mv file.txt /tmp/                   # move to different location
rm file.txt                         # delete file
rm -rf mydir/                       # delete directory recursively (careful!)

# rm -rf with a typo can delete system files. Always double check the path.
```

---

## Key Insight for DevOps

In production you'll often SSH into servers with no GUI and no file manager. Being fast in the terminal — navigating, finding files, reading logs — is the difference between a 2-minute fix and a 20-minute one. Practice until it's muscle memory.
