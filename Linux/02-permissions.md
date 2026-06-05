# Users, Groups & Permissions

Linux is a multi-user OS. Every file has an owner, a group, and a permission set. Understanding this is critical — misconfigured permissions are the cause of a huge number of "why isn't this working" moments in DevOps.

---

## Users and Groups

```bash
whoami                    # current user
id                        # uid, gid, and all groups you belong to
cat /etc/passwd           # all users on the system
cat /etc/group            # all groups

# Add a user
sudo useradd -m joon      # -m creates home directory
sudo passwd joon          # set password

# Add user to a group
sudo usermod -aG docker joon    # -a = append, -G = group
# Common groups: sudo, docker, www-data

# Switch user
su - joon                 # switch to joon (- loads their environment)
sudo su -                 # switch to root
```

---

## File Permission Model

Every file has three permission sets: **owner**, **group**, **others**

```
-rwxr-xr--  1 joon devops 1234 Jun 1 10:00 deploy.sh
│└──┘└──┘└──┘
│ │   │   └── others: r-- (read only)
│ │   └─────── group:  r-x (read + execute)
│ └─────────── owner:  rwx (read + write + execute)
└───────────── file type: - (file), d (dir), l (symlink)
```

**Permission values:**

| Symbol | Meaning | Numeric |
|--------|---------|---------|
| r | read | 4 |
| w | write | 2 |
| x | execute | 1 |
| - | none | 0 |

`rwx = 4+2+1 = 7`, `r-x = 4+0+1 = 5`, `r-- = 4+0+0 = 4`

---

## chmod — Change Permissions

```bash
# Numeric (most common in DevOps)
chmod 755 deploy.sh       # rwxr-xr-x  — owner full, group/others read+execute
chmod 644 config.yaml     # rw-r--r--  — owner read+write, others read only
chmod 600 private.key     # rw-------  — owner only (SSH keys MUST be this)
chmod 777 /tmp/shared     # rwxrwxrwx  — everyone everything (avoid in prod)

# Symbolic
chmod +x script.sh        # add execute for everyone
chmod u+x,g-w script.sh  # user add execute, group remove write
chmod o-rwx secret.txt    # remove all permissions for others
```

---

## chown — Change Owner

```bash
chown joon file.txt             # change owner to joon
chown joon:devops file.txt      # change owner and group
chown -R joon:devops /app/      # recursive (whole directory)
```

---

## sudo — Run as Root

```bash
sudo command              # run single command as root
sudo -i                   # open root shell
sudo -l                   # see what you're allowed to run with sudo
visudo                    # safely edit /etc/sudoers

# Give user passwordless sudo (in /etc/sudoers):
joon ALL=(ALL) NOPASSWD: ALL
```

---

## Special Permissions

```bash
# Sticky bit — only owner can delete files in a directory
chmod +t /shared/          # common on /tmp
# Shows as 't' in others execute bit: drwxrwxrwt

# SUID — run file as its owner, not the caller
chmod u+s /usr/bin/passwd  # passwd runs as root even when called by normal user

# SGID — new files inherit group of directory
chmod g+s /team/shared/
```

---

## Real-World Patterns

```bash
# Web server files
chown -R www-data:www-data /var/www/html
chmod -R 755 /var/www/html

# SSH private keys (must be 600 or SSH will refuse them)
chmod 600 ~/.ssh/id_rsa
chmod 700 ~/.ssh/

# Scripts in CI/CD
chmod +x ./scripts/deploy.sh

# App secrets — readable only by app user
chmod 640 /etc/app/secrets.env
chown root:appuser /etc/app/secrets.env
```

---

## Key Insight for DevOps

SSH will silently reject connections if your private key permissions are wrong. App containers will crash if config files aren't readable by the process user. Permission errors are often subtle — always check `ls -la` when something "just won't start."
