# Lab 01 — Filesystem Navigation

**Goal:** Get comfortable navigating the Linux filesystem using only the terminal.

**Time:** ~20 minutes  
**Prerequisites:** A Linux machine (local VM, EC2 instance, or WSL on Windows)

---

## Tasks

### Part 1 — Explore the Filesystem

1. Open a terminal. Find out where you are right now.

2. List everything in your current directory, including hidden files, with file sizes in human-readable format.

3. Navigate to `/etc`. List all files that end in `.conf`.

4. Navigate to `/var/log`. List all files sorted by modification time (newest first).

5. Go back to your home directory using **two different methods**.

6. Navigate to `/tmp`, then back to `/etc/nginx` (or `/etc/ssh` if nginx isn't installed) using a **relative path** from `/tmp`.

---

### Part 2 — Finding Files

7. Find all `.log` files under `/var/log` that were modified in the last 24 hours.

8. Find all files in `/etc` larger than 100KB.

9. Find the location of the `sshd` binary.

10. Find all files owned by `root` in your home directory (there probably won't be any — that's fine, just run the command and understand the output).

---

### Part 3 — Viewing Files

11. Print the first 10 lines of `/etc/passwd`. What does each field mean?  
    *(Hint: the format is `username:password:UID:GID:comment:home:shell`)*

12. Print the last 5 lines of `/etc/passwd`.

13. View `/etc/os-release`. What OS and version are you running?

14. Search `/etc/passwd` for the line containing your current username.

15. Count how many lines are in `/etc/passwd` (each line = one user).

---

### Part 4 — Creating & Moving Files

16. Create a new directory called `devops-lab` in your home directory.

17. Inside it, create three empty files: `server1.txt`, `server2.txt`, `server3.txt`.

18. Copy `server1.txt` to a new file called `server1-backup.txt` inside the same directory.

19. Move `server2.txt` to `/tmp/`.

20. Rename `server3.txt` to `webserver.txt`.

21. Delete `server1-backup.txt`.

22. Verify the final state: your `devops-lab` directory should contain only `server1.txt` and `webserver.txt`.

---

## Expected Outcomes

By the end of this lab you should be able to:
- Navigate anywhere in the filesystem without thinking about it
- Find files by name, size, age, and owner
- Read and search file contents from the terminal
- Create, copy, move, and delete files and directories

---

## Solution

Stuck? See [solutions/lab-01-solution.md](../solutions/lab-01-solution.md)  
*(Try everything yourself first — the commands matter less than building the muscle memory.)*
