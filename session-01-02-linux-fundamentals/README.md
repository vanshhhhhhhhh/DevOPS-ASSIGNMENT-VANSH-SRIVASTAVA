# Session 01 & 02: Linux Fundamentals

**Name:** Vansh Srivastava
**Enrollment No.:** 24bcs10567
**Session:** 01 & 02

Session 01 was the DevOps engineer roadmap: monolith vs microservices, the DevOps lifecycle (Plan, Code, Build, Test, Release, Deploy, Operate, Monitor), the tool list (Git and GitHub, Docker, Python, Linux, networking, CI/CD, cloud, Kubernetes, Terraform, Ansible, monitoring, GitOps, DevSecOps) and the job roles. The roadmap calls Linux "the heart of DevOps", and Session 02 was about Linux, so all the homework for these two sessions is Linux practice. I did the four tasks in a throwaway Ubuntu 24.04 container and in the Colima VM (for `journalctl`, because that needs systemd), and saved the practice scripts I used so every output below can be reproduced.

## Folder structure

```text
session-01-02-linux-fundamentals/
├── README.md                  # this file: explanations and the real output
├── .gitignore
└── practice/
    ├── lib.sh                 # run/block helpers: print "$ command", then its output
    ├── task1-links.sh         # Task 1: soft link vs hard link practice
    ├── task2-users.sh         # Task 2: useradd vs adduser practice
    ├── task3-journalctl.sh    # Task 3: journalctl practice (runs inside the Colima VM)
    └── task4-cheatsheet.sh    # Task 4: commands from the course cheat sheets
```

## Environment

```bash
$ sw_vers -productVersion; uname -m
26.6.2
arm64
$ docker version --format 'client {{.Client.Version}} / server {{.Server.Version}}'
client 29.8.2 / server 29.5.2
$ colima version | head -1
colima version 0.10.3
$ docker ps --filter name=s01-ubuntu --format '{{.Names}}  {{.Image}}  {{.Status}}'
s01-ubuntu  public.ecr.aws/docker/library/ubuntu:24.04  Up 2 minutes
$ docker exec s01-ubuntu grep PRETTY_NAME /etc/os-release
PRETTY_NAME="Ubuntu 24.04.5 LTS"
```

- Mac: macOS 26 on Apple Silicon, Docker through Colima.
- Linux box for Tasks 1, 2 and 4: a throwaway container `s01-ubuntu` (Ubuntu 24.04.5). I pulled the image from `public.ecr.aws/docker/library/ubuntu:24.04` (the official Docker library image mirrored on AWS ECR) because my first `docker run ... ubuntu:24.04` failed: Docker Hub answered `failed to resolve reference "docker.io/library/ubuntu:24.04" ... 429 Too Many Requests` (Docker Hub limits anonymous pulls). A retry later in the session worked, and it is the same image (same digest `sha256:534baea6...`), but I had already built everything on the mirror image. I started it with `--init` so that a real init process reaps finished child processes.
- Task 3 (`journalctl`): the Colima VM itself, which is Ubuntu 24.04.4 with systemd 255. A Docker container has no systemd and no journal, so `journalctl` is not available there. I only read logs in the VM and changed nothing.

How I set up the container and ran the scripts (the apt output is long, so I did not paste it):

```bash
$ docker run -d --init --name s01-ubuntu --hostname s01-ubuntu public.ecr.aws/docker/library/ubuntu:24.04 sleep infinity
$ docker exec s01-ubuntu bash -c 'apt-get update && apt-get install -y --no-install-recommends adduser perl iproute2 iputils-ping iputils-tracepath traceroute dnsutils bind9-host curl wget ca-certificates net-tools netcat-openbsd telnet tree file less lsof sudo cron ipcalc tcpdump'
$ docker cp practice s01-ubuntu:/root/practice
$ docker exec s01-ubuntu bash /root/practice/task1-links.sh      # same for task2 and task4
$ bash practice/task3-journalctl.sh                              # runs on the Mac, uses colima ssh
```

Each script uses `run '<command>'` from `practice/lib.sh`, which prints `$ <command>` and then runs it, so the blocks below are the scripts' own output. Commands ran as `root` in the container, so `sudo` is not needed there; on a normal Ubuntu machine the user-management and package commands need `sudo`.

## Task 1: Soft Link & Hard Link

### The difference

Every file on a Linux filesystem is an **inode** (the metadata and the pointers to the data blocks). A file name is just a directory entry that points to an inode.

- A **hard link** is one more name for the same inode. Both names are equal; there is no "original" and "copy". The inode keeps a link count, and the data is freed only when the count reaches 0.
- A **soft link** (symbolic link, symlink) is a separate small file with its own inode, whose content is a path to the target. If the target is deleted or moved, the symlink is left "dangling".

| | Hard link | Soft (symbolic) link |
|---|---|---|
| Command | `ln target linkname` | `ln -s target linkname` |
| Inode | same inode as the target | its own new inode |
| What it stores | nothing extra, it is a directory entry | the path to the target |
| `ls -l` shows | a normal file, link count goes up | `l` file type and `link -> target` |
| Target deleted | data still there through the hard link | link breaks (dangling) |
| Directories | not allowed | allowed |
| Across filesystems/partitions | not allowed | allowed |
| Size | same as the file | length of the path string |

### Create both links

```bash
$ rm -rf ~/links-demo && mkdir ~/links-demo && cd ~/links-demo
$ echo "Hello from the original file" > original.txt
$ ln original.txt hardlink.txt
$ ln -s original.txt softlink.txt
$ ls -li
total 8
3301731 -rw-r--r-- 2 root root 29 Oct  7 17:54 hardlink.txt
3301731 -rw-r--r-- 2 root root 29 Oct  7 17:54 original.txt
3301732 lrwxrwxrwx 1 root root 12 Oct  7 17:54 softlink.txt -> original.txt
```

The first column of `ls -li` is the inode number. `original.txt` and `hardlink.txt` have the same inode (3301731) and the link count (third column) is 2. `softlink.txt` has a different inode, type `l`, and shows where it points.

```bash
$ stat -c "%n | inode=%i | links=%h | type=%F | size=%s" original.txt hardlink.txt softlink.txt
original.txt | inode=3301731 | links=2 | type=regular file | size=29
hardlink.txt | inode=3301731 | links=2 | type=regular file | size=29
softlink.txt | inode=3301732 | links=1 | type=symbolic link | size=12
$ readlink softlink.txt
original.txt
$ readlink -f softlink.txt
/root/links-demo/original.txt
```

The symlink's size is 12 bytes, which is exactly the length of the text `original.txt`. `readlink` shows the stored path, `readlink -f` resolves it to an absolute path.

### Edit through the links

```bash
$ echo "Line added through the HARD link" >> hardlink.txt
$ echo "Line added through the SOFT link" >> softlink.txt
$ cat original.txt
Hello from the original file
Line added through the HARD link
Line added through the SOFT link
```

Writing through either link changes the same data, because both end up at inode 3301731.

### Delete the original

```bash
$ rm original.txt
$ ls -li
total 4
3301731 -rw-r--r-- 1 root root 95 Oct  7 17:54 hardlink.txt
3301732 lrwxrwxrwx 1 root root 12 Oct  7 17:54 softlink.txt -> original.txt
$ cat hardlink.txt
Hello from the original file
Line added through the HARD link
Line added through the SOFT link
$ cat softlink.txt
cat: softlink.txt: No such file or directory
$ find . -xtype l
./softlink.txt
```

After `rm original.txt` the hard link still has all the data (the link count dropped from 2 to 1). The soft link still exists but points to a name that is gone, so `cat` fails. `find -xtype l` is a handy way to find broken symlinks.

### Recreate a file with the same name

```bash
$ echo "I am a brand new original.txt" > original.txt
$ ls -li
total 8
3301731 -rw-r--r-- 1 root root 95 Oct  7 17:54 hardlink.txt
3301733 -rw-r--r-- 1 root root 30 Oct  7 17:54 original.txt
3301732 lrwxrwxrwx 1 root root 12 Oct  7 17:54 softlink.txt -> original.txt
$ cat softlink.txt
I am a brand new original.txt
$ cat hardlink.txt
Hello from the original file
Line added through the HARD link
Line added through the SOFT link
```

This is the clearest difference for me: the new `original.txt` gets a new inode (3301733). The soft link works again because it only follows the name, but the hard link still holds the old data because it is tied to the old inode, not to the name.

### Directories and other filesystems

```bash
$ mkdir mydir
$ ln mydir mydir-hard
ln: mydir: hard link not allowed for directory
$ ln -s mydir mydir-soft
$ ls -ld mydir mydir-soft
drwxr-xr-x 2 root root 4096 Oct  7 17:54 mydir
lrwxrwxrwx 1 root root    5 Oct  7 17:54 mydir-soft -> mydir
$ df -h /root /dev/shm | sed 1d
overlay          59G   27G   29G  49% /
shm              64M     0   64M   0% /dev/shm
$ ln hardlink.txt /dev/shm/cross-fs-hard.txt
ln: failed to create hard link '/dev/shm/cross-fs-hard.txt' => 'hardlink.txt': Invalid cross-device link
$ ln -s ~/links-demo/hardlink.txt /dev/shm/cross-fs-soft.txt
$ cat /dev/shm/cross-fs-soft.txt
Hello from the original file
Line added through the HARD link
Line added through the SOFT link
```

Hard links to directories are refused (they could create loops in the directory tree). `/dev/shm` is a separate `tmpfs` filesystem, and a hard link to it fails with `Invalid cross-device link` because inode numbers are only unique inside one filesystem. A soft link across filesystems works fine.

### Delete links

```bash
$ rm softlink.txt
$ unlink mydir-soft
$ rm /dev/shm/cross-fs-soft.txt
$ stat -c "%n links=%h" hardlink.txt
hardlink.txt links=1
$ ln hardlink.txt second-hard.txt
$ stat -c "%n links=%h" hardlink.txt
hardlink.txt links=2
$ rm second-hard.txt
$ stat -c "%n links=%h" hardlink.txt
hardlink.txt links=1
$ ls -li
total 12
3301731 -rw-r--r-- 1 root root   95 Oct  7 17:54 hardlink.txt
3301734 drwxr-xr-x 2 root root 4096 Oct  7 17:54 mydir
3301733 -rw-r--r-- 1 root root   30 Oct  7 17:54 original.txt
$ cd ~ && rm -rf ~/links-demo && ls -d ~/links-demo
ls: cannot access '/root/links-demo': No such file or directory
```

`rm` or `unlink` on a symlink removes only the link, never the target. Adding and removing a second hard link moves the link count 1 -> 2 -> 1 while the data stays.

### Interview questions I prepared

1. **What is the difference between a soft link and a hard link?** A hard link is another directory entry for the same inode; a soft link is a separate file that stores a path. A hard link survives deletion of the other name; a soft link breaks.
2. **How do you create each?** `ln file hardlink` and `ln -s file softlink`. Add `-f` to replace an existing link, `-n` to treat an existing symlink to a directory as a file.
3. **Why can't you hard link a directory?** It could create cycles, which would break tools like `find`, `du` and `fsck`. The kernel only creates the special `.` and `..` entries itself.
4. **Why can't a hard link cross filesystems?** Inode numbers are only unique within one filesystem, so a directory entry on filesystem B cannot point to an inode on filesystem A.
5. **How do you see if two files are hard links of each other?** Compare inode numbers with `ls -li` or `stat -c %i`, or use `find / -samefile file`. The link count in `ls -l` tells how many names an inode has.
6. **What happens to a symlink when the target is deleted?** It becomes dangling. `find . -xtype l` lists such links.
7. **When would you use each?** Soft links for things like `/etc/nginx/sites-enabled/site -> ../sites-available/site`, switching versions (`current -> releases/v2`), or shortcuts across disks. Hard links are used by backup tools (for example `rsync --link-dest`) to keep many snapshots without copying unchanged files.
8. **Does `rm` on a soft link delete the target?** No, only the link.

## Task 2: adduser vs useradd

### The difference

| | `useradd` | `adduser` |
|---|---|---|
| What it is | low-level binary from the `passwd` package (shadow-utils), on every Linux distro | Debian/Ubuntu Perl script from the `adduser` package, a friendlier front end that calls `useradd`, `passwd`, `chfn` |
| Interactive | no, everything comes from flags | yes, asks for the password and the full name |
| Home directory | not created unless you pass `-m` | created and filled from `/etc/skel` |
| Login shell | `/bin/sh` by default (`useradd -D`) | `/bin/bash` (`DSHELL` in `/etc/adduser.conf`) |
| Password | none, account is locked until you run `passwd` | set during creation |
| Defaults from | `/etc/default/useradd`, `/etc/login.defs` | `/etc/adduser.conf` |
| Good for | scripts, Dockerfiles, other distros | creating users by hand on Ubuntu/Debian |

### Which one is preferred on Ubuntu and why

`adduser` is the recommended command on Ubuntu and Debian. It does the whole job in one step (home directory, skeleton files, bash shell, password, full name, group, policy-conformant UID) and asks for what it needs, so it is harder to end up with a broken account. The man pages say the same thing:

```bash
$ curl -sL https://manpages.ubuntu.com/manpages/noble/man8/useradd.8.html | sed 's/<[^>]*>//g' | grep -A1 'low level'
useradd is a low level utility for adding users. On Debian,
    administrators should usually use adduser(8) instead.
$ curl -sL https://manpages.ubuntu.com/manpages/noble/man8/adduser.8.html | sed 's/<[^>]*>//g' | grep -B2 -A3 'friendlier front ends'
adduser and addgroup add users and groups to the
    system according to command line options and configuration information in
    /etc/adduser.conf. They are friendlier front ends to the low level
    tools like useradd, groupadd and usermod programs, by
    default choosing Debian policy conformant UID and GID values, creating a
    home directory with skeletal configuration, running a custom script, and
```

`useradd` is still useful in scripts and Dockerfiles and is the same on every distro, but you have to remember `-m -s /bin/bash` and set a password yourself.

### Where each command comes from

```bash
$ dpkg -S /usr/sbin/useradd /usr/sbin/adduser
passwd: /usr/sbin/useradd
adduser: /usr/sbin/adduser
$ file /usr/sbin/useradd /usr/sbin/adduser
/usr/sbin/useradd: ELF 64-bit LSB pie executable, ARM aarch64, version 1 (SYSV), dynamically linked, interpreter /lib/ld-linux-aarch64.so.1, BuildID[sha1]=483f79642f7a936acdeb2cb2fd1c4e70c2f0ef9d, for GNU/Linux 3.7.0, stripped
/usr/sbin/adduser: Perl script text executable
$ useradd -D
GROUP=100
HOME=/home
INACTIVE=-1
EXPIRE=
SHELL=/bin/sh
SKEL=/etc/skel
CREATE_MAIL_SPOOL=no
LOG_INIT=yes
$ grep -E "^#(DSHELL|DHOME|SKEL|FIRST_UID|LAST_UID|USERGROUPS|ADD_EXTRA_GROUPS|EXTRA_GROUPS)=" /etc/adduser.conf
#DSHELL=/bin/bash
#SKEL=/etc/skel
#FIRST_UID=1000
#LAST_UID=59999
#USERGROUPS=yes
#EXTRA_GROUPS="users"
#ADD_EXTRA_GROUPS=0
```

`useradd` is a compiled program, `adduser` is a Perl script. The `adduser.conf` lines are commented out because they show the built-in defaults (bash shell, `/etc/skel`, UIDs from 1000). On the Mac I also checked that the minimal Docker image does not even ship `adduser`, while `useradd` is there:

```bash
$ docker run --rm public.ecr.aws/docker/library/ubuntu:24.04 bash -c 'command -v useradd; command -v adduser || echo "adduser: not installed in the minimal image"'
/usr/sbin/useradd
adduser: not installed in the minimal image
```

### useradd without options

```bash
$ useradd testuser1
$ getent passwd testuser1
testuser1:x:1001:1001::/home/testuser1:/bin/sh
$ ls -ld /home/testuser1
ls: cannot access '/home/testuser1': No such file or directory
$ passwd -S testuser1
testuser1 L 2026-10-07 0 99999 7 -1
```

With no flags, `useradd` gave the user `/bin/sh`, did not create `/home/testuser1`, and the password status is `L` (locked, no password). This user cannot log in until I fix all of that by hand.

### useradd with the right flags

```bash
$ useradd -m -s /bin/bash -c "Test User Two" testuser2
$ getent passwd testuser2
testuser2:x:1002:1002:Test User Two:/home/testuser2:/bin/bash
$ ls -la /home/testuser2
total 20
drwxr-x--- 2 testuser2 testuser2 4096 Oct  7 17:54 .
drwxr-xr-x 1 root      root      4096 Oct  7 17:54 ..
-rw-r--r-- 1 testuser2 testuser2  220 Mar 31  2024 .bash_logout
-rw-r--r-- 1 testuser2 testuser2 3771 Mar 31  2024 .bashrc
-rw-r--r-- 1 testuser2 testuser2  807 Mar 31  2024 .profile
```

With `-m -s /bin/bash -c` the result is usable, but I had to know the flags.

### Create a test user with adduser (the recommended way)

`adduser` is interactive. `docker exec` has no terminal, so the script feeds my answers to the prompts through a pseudo-terminal (`script`) one by one; the `answers` function in `practice/task2-users.sh` just prints them with small pauses. On a normal Ubuntu shell this is simply `sudo adduser vanshtest` and typing the answers. The password is a throwaway demo value.

```bash
$ answers | script -qec "adduser vanshtest" /dev/null
info: Adding user `vanshtest' ...
info: Selecting UID/GID from range 1000 to 59999 ...
info: Adding new group `vanshtest' (1003) ...
info: Adding new user `vanshtest' (1003) with group `vanshtest (1003)' ...
info: Creating home directory `/home/vanshtest' ...
info: Copying files from `/etc/skel' ...
New password: 
Retype new password: 
passwd: password updated successfully
Changing the user information for vanshtest
Enter the new value, or press ENTER for the default
	Full Name []: Vansh Test User
	Room Number []: 
	Work Phone []: 
	Home Phone []: 
	Other []: 
Is the information correct? [Y/n] Y
info: Adding new user `vanshtest' to supplemental / extra groups `users' ...
info: Adding user `vanshtest' to group `users' ...
```

```bash
$ getent passwd vanshtest
vanshtest:x:1003:1003:Vansh Test User,,,:/home/vanshtest:/bin/bash
$ id vanshtest
uid=1003(vanshtest) gid=1003(vanshtest) groups=1003(vanshtest),100(users)
$ passwd -S vanshtest
vanshtest P 2026-10-07 0 99999 7 -1
$ ls -la /home/vanshtest
total 20
drwxr-x--- 2 vanshtest vanshtest 4096 Oct  7 17:54 .
drwxr-xr-x 1 root      root      4096 Oct  7 17:54 ..
-rw-r--r-- 1 vanshtest vanshtest  220 Oct  7 17:54 .bash_logout
-rw-r--r-- 1 vanshtest vanshtest 3771 Oct  7 17:54 .bashrc
-rw-r--r-- 1 vanshtest vanshtest  807 Oct  7 17:54 .profile
$ usermod -aG sudo vanshtest
$ groups vanshtest
vanshtest : vanshtest sudo users
$ su - vanshtest -c "whoami; pwd; echo \$SHELL"
vanshtest
/home/vanshtest
/bin/bash
```

One command gave a full account: bash shell, home directory with `.bashrc`, `.profile`, `.bash_logout` copied from `/etc/skel`, a password (status `P`), a private group, the full name in the GECOS field and membership of the `users` group. `usermod -aG sudo` added it to `sudo` (`-a` appends; without it `-G` would replace the supplementary groups). `su -` shows the login works. The UID is 1003 because the image already has a `ubuntu` user with UID 1000 and my two `useradd` test users took 1001 and 1002.

For scripts, `adduser` also has a non-interactive form:

```bash
$ adduser --disabled-password --comment "Script User" scriptuser
info: Adding user `scriptuser' ...
info: Selecting UID/GID from range 1000 to 59999 ...
info: Adding new group `scriptuser' (1004) ...
info: Adding new user `scriptuser' (1004) with group `scriptuser (1004)' ...
info: Creating home directory `/home/scriptuser' ...
info: Copying files from `/etc/skel' ...
info: Adding new user `scriptuser' to supplemental / extra groups `users' ...
info: Adding user `scriptuser' to group `users' ...
$ passwd -S scriptuser
scriptuser L 2026-10-07 0 99999 7 -1
```

### Clean up

```bash
$ userdel testuser1
$ userdel -r testuser2
userdel: testuser2 mail spool (/var/mail/testuser2) not found
$ deluser --remove-home scriptuser
info: Looking for files to backup/remove ...
info: Removing files ...
info: Removing crontab ...
info: Removing user `scriptuser' ...
$ deluser --remove-home vanshtest
info: Looking for files to backup/remove ...
info: Removing files ...
info: Removing crontab ...
info: Removing user `vanshtest' ...
$ getent passwd testuser1 testuser2 scriptuser vanshtest || echo "no test users left"
no test users left
$ ls /home
ubuntu
```

`userdel -r` / `deluser --remove-home` also delete the home directory. (`deluser --remove-home` needs the full `perl` package, which the minimal image does not have, so I installed `perl` in the setup step.)

## Task 3: journalctl

### What it is used for

On systemd Linux systems, `systemd-journald` collects logs from the kernel, from early boot, from every service's stdout/stderr and from syslog, and stores them in a binary, indexed journal. `journalctl` is the tool to read and filter that journal. Instead of searching many files in `/var/log`, I can filter by service (`-u`), time (`--since`/`--until`), boot (`-b`), priority (`-p`) or text (`--grep`), and follow new lines live (`-f`).

| Option | What it does |
|---|---|
| `-n N` | last N lines |
| `-u unit` | only one service (can repeat) |
| `-f` | follow new lines, like `tail -f` |
| `-b` / `--list-boots` | current boot / list boots |
| `-k` | kernel messages (like `dmesg`) |
| `-p err` | priority filter (emerg, alert, crit, err, warning, notice, info, debug) |
| `--since "15 min ago"`, `--until`, `--since today` | time window |
| `-r` | newest first |
| `-o short-iso`, `-o cat`, `-o json-pretty` | output format |
| `--grep text` | filter by message text |
| `-x -e` | add explanations and jump to the end (the `journalctl -xe` from the cheat sheet) |
| `--disk-usage` | how much space the journal uses |
| `--no-pager` | print directly instead of opening `less` |

### Where I ran it

```bash
$ colima ssh -- grep PRETTY_NAME /etc/os-release
PRETTY_NAME="Ubuntu 24.04.4 LTS"
$ colima ssh -- ps -p 1 -o comm=
systemd
$ colima ssh -- systemctl --version | head -1
systemd 255 (255.4-1ubuntu8.15)
$ colima ssh -- id -nG
vanshsrivastava docker systemd-journal
```

The Colima VM runs systemd as PID 1, and my VM user is in the `systemd-journal` group, so it can read the system journal without `sudo`. Every command is `colima ssh -- <command>` from the Mac.

### System logs

```bash
$ colima ssh -- journalctl --disk-usage
Archived and active journals take up 8.0M in the file system.
$ colima ssh -- journalctl --list-boots --no-pager
IDX BOOT ID                          FIRST ENTRY                 LAST ENTRY
  0 4a59c6dd58b34c6e8486fc57556add43 Wed 2026-10-07 23:04:31 IST Wed 2026-10-07 23:21:41 IST
$ colima ssh -- journalctl -n 8 --no-pager
Oct 07 23:21:19 colima kernel: br-0a4836d4c640: port 3(veth856ff98) entered forwarding state
Oct 07 23:21:19 colima dockerd[1578]: time="2026-10-07T23:21:19.201119952+05:30" level=info msg="sbJoin: gwep4 ''->'20ba501b3f86', gwep6 ''->''" eid=20ba501b3f86 ep=s20-cadvisor net=s20-monitoring-net nid=0a4836d4c640 spanID=f0db29fb026a9bb7 traceID=1cf0a070ddb2b015ad5bf7f4f6fc3910
Oct 07 23:21:19 colima systemd[1]: mnt-lima\x2dcolima-docker-rootfs-overlayfs-7d7718cfd6a32f547ee7f03e7bbad955069673f47bc049bb5f7d70305927e45b.mount: Deactivated successfully.
Oct 07 23:21:19 colima systemd[1]: var-lib-docker-rootfs-overlayfs-7d7718cfd6a32f547ee7f03e7bbad955069673f47bc049bb5f7d70305927e45b.mount: Deactivated successfully.
Oct 07 23:21:20 colima systemd-networkd[443]: veth856ff98: Gained IPv6LL
Oct 07 23:21:21 colima lima-guestagent[1156]: time="2026-10-07T23:21:21+05:30" level=info msg="SyncTime: system time synchronized with host (drift was 135.371ms)"
Oct 07 23:21:31 colima lima-guestagent[1156]: time="2026-10-07T23:21:31+05:30" level=info msg="SyncTime: system time synchronized with host (drift was 128.059858ms)"
Oct 07 23:21:41 colima lima-guestagent[1156]: time="2026-10-07T23:21:41+05:30" level=info msg="SyncTime: system time synchronized with host (drift was 134.710742ms)"
$ colima ssh -- journalctl -k -n 5 --no-pager
Oct 07 23:21:19 colima kernel: veth856ff98: entered allmulticast mode
Oct 07 23:21:19 colima kernel: veth856ff98: entered promiscuous mode
Oct 07 23:21:19 colima kernel: eth0: renamed from veth4dd5f8a
Oct 07 23:21:19 colima kernel: br-0a4836d4c640: port 3(veth856ff98) entered blocking state
Oct 07 23:21:19 colima kernel: br-0a4836d4c640: port 3(veth856ff98) entered forwarding state
$ colima ssh -- journalctl -b -p err -n 5 --no-pager
Oct 07 23:04:36 lima-colima sudo[1284]: vanshsrivastava : unable to resolve host lima-colima: Temporary failure in name resolution
Oct 07 23:04:36 lima-colima sudo[1293]: vanshsrivastava : unable to resolve host lima-colima: Temporary failure in name resolution
Oct 07 23:04:39 lima-colima sudo[1299]: vanshsrivastava : unable to resolve host lima-colima: Temporary failure in name resolution
Oct 07 23:04:42 lima-colima sudo[1307]: vanshsrivastava : unable to resolve host lima-colima: Temporary failure in name resolution
Oct 07 23:04:43 colima systemd[1]: Failed to start cloud-final.service - Cloud-init: Final Stage.
```

- `--list-boots` shows a single boot (the VM was started at 23:04 IST).
- The last system lines come from different programs mixed together: the kernel and `systemd-networkd` attaching a new container's virtual interface (`veth...`) to a Docker bridge, `systemd` releasing the overlay mount of a container that stopped, `dockerd`, and the Lima guest agent syncing the clock with the Mac.
- `-k` shows only the kernel messages: the new `veth` interface being renamed to `eth0` inside the container and its bridge port going to `forwarding` state.
- `-b -p err` shows only errors from this boot: `sudo` could not resolve the VM's hostname early in boot and `cloud-init`'s final stage failed. Both happened during startup and Docker still came up fine.

### Service status

```bash
$ colima ssh -- systemctl status docker --no-pager -n 0
● docker.service - Docker Application Container Engine
     Loaded: loaded (/usr/lib/systemd/system/docker.service; enabled; preset: enabled)
    Drop-In: /etc/systemd/system/docker.service.d
             └─docker.conf
     Active: active (running) since Wed 2026-10-07 23:04:47 IST; 16min ago
TriggeredBy: ● docker.socket
       Docs: https://docs.docker.com
   Main PID: 1578 (dockerd)
      Tasks: 264
     Memory: 195.6M (peak: 198.2M)
        CPU: 48.270s
     CGroup: /system.slice/docker.service
             ├─ 1578 /usr/bin/dockerd -H fd:// --containerd=/run/containerd/containerd.sock --host-gateway-ip=192.168.5.2
...
```

`systemctl status` shows the service state and PID; `-n 0` hides the log lines because I read those with `journalctl`. I cut the long list of `docker-proxy` processes.

### Logs for a specific service: docker

```bash
$ colima ssh -- journalctl -u docker.service -n 8 --no-pager
Oct 07 23:20:27 colima dockerd[1578]: time="2026-10-07T23:20:27.913756338+05:30" level=info msg="sbJoin: gwep4 ''->'01010c483d8b', gwep6 ''->''" eid=01010c483d8b ep=s07-multistage-hello net=bridge nid=ee27389cf7a0
Oct 07 23:20:30 colima dockerd[1578]: time="2026-10-07T23:20:30.171445281+05:30" level=error msg="healthcheck failed fatally" error="session healthcheck failed fatally: Unavailable: connection error: desc = \"transport: Error while dialing: only one connection allowed\""
Oct 07 23:20:30 colima dockerd[1578]: time="2026-10-07T23:20:30.249125479+05:30" level=error msg="healthcheck failed fatally" error="session healthcheck failed fatally: Unavailable: connection error: desc = \"transport: Error while dialing: only one connection allowed\""
Oct 07 23:20:40 colima dockerd[1578]: time="2026-10-07T23:20:40.410145559+05:30" level=info msg="received task-delete event from containerd" container=fff34d07e781e57cdc51e43a30eb4754d5642770472034aa5ac01e49c4694190 module=libcontainerd namespace=moby topic=/tasks/delete type="*events.TaskDelete"
Oct 07 23:21:18 colima dockerd[1578]: time="2026-10-07T23:21:18.739704346+05:30" level=info msg="image pulled" digest="sha256:e75bdb03b74b0b6995f208f166fead2e6e555dde73e44200113bb26f41b1981d" remote="ghcr.io/google/cadvisor:v0.57.0" spanID=6274c2661549a7c5 traceID=1cf0a070ddb2b015ad5bf7f4f6fc3910
Oct 07 23:21:18 colima dockerd[1578]: time="2026-10-07T23:21:18.998545154+05:30" level=info msg="received task-delete event from containerd" container=7d7718cfd6a32f547ee7f03e7bbad955069673f47bc049bb5f7d70305927e45b module=libcontainerd namespace=moby topic=/tasks/delete type="*events.TaskDelete"
Oct 07 23:21:19 colima dockerd[1578]: time="2026-10-07T23:21:19.133586902+05:30" level=warning msg="path in container /dev/kmsg already exists in privileged mode" container=e8ba8cc301c492d2588b350c74891a63ef4c111f2db99b46f851568e61222807 spanID=f0db29fb026a9bb7 traceID=1cf0a070ddb2b015ad5bf7f4f6fc3910
Oct 07 23:21:19 colima dockerd[1578]: time="2026-10-07T23:21:19.201119952+05:30" level=info msg="sbJoin: gwep4 ''->'20ba501b3f86', gwep6 ''->''" eid=20ba501b3f86 ep=s20-cadvisor net=s20-monitoring-net nid=0a4836d4c640 spanID=f0db29fb026a9bb7 traceID=1cf0a070ddb2b015ad5bf7f4f6fc3910
$ colima ssh -- sh -c "journalctl -u docker.service -b --no-pager | head -4"
Oct 07 23:04:35 lima-colima systemd[1]: Starting docker.service - Docker Application Container Engine...
Oct 07 23:04:35 lima-colima dockerd[633]: time="2026-10-07T23:04:35.442562418+05:30" level=info msg="Starting up"
Oct 07 23:04:35 lima-colima dockerd[633]: time="2026-10-07T23:04:35.443631835+05:30" level=info msg="OTEL tracing is not configured, using no-op tracer provider"
Oct 07 23:04:35 lima-colima dockerd[633]: time="2026-10-07T23:04:35.443913251+05:30" level=info msg="CDI directory does not exist, skipping" dir=/etc/cdi
$ colima ssh -- journalctl -u docker.service --since "15 min ago" --no-pager | wc -l
     211
$ colima ssh -- journalctl -u docker.service -p warning --since "15 min ago" --no-pager
-- No entries --
$ colima ssh -- sh -c "journalctl -u docker.service --since \"15 min ago\" --no-pager | grep -c level=error"
53
```

- `-u docker.service -n 8` gives the latest Docker daemon lines (containers being started and removed by me and by other work on this Mac).
- `-b | head -4` shows the first lines of this boot, the daemon starting up.
- In the last 15 minutes there were 211 Docker lines.
- Interesting finding: `-p warning` returned **no entries**, although 53 of those lines contain `level=error`. `dockerd` writes plain text to stdout/stderr, and journald stores all of it at the default priority 6 (info); the `level=error` is only text inside the message. So for Docker I have to search the text (`--grep` or `grep`), while `-p` only works for programs that send a real syslog priority (like `sudo` and `systemd` in the `-p err` example above).

### Logs for other services: containerd and ssh

```bash
$ colima ssh -- journalctl -u containerd -n 5 --no-pager -o short-iso
2026-10-07T23:20:40+05:30 colima containerd[1497]: time="2026-10-07T23:20:40.410198380+05:30" level=info msg="cleaning up dead shim" id=fff34d07e781e57cdc51e43a30eb4754d5642770472034aa5ac01e49c4694190 namespace=moby
2026-10-07T23:21:18+05:30 colima containerd[1497]: time="2026-10-07T23:21:18.998604324+05:30" level=info msg="shim disconnected" id=7d7718cfd6a32f547ee7f03e7bbad955069673f47bc049bb5f7d70305927e45b namespace=moby
2026-10-07T23:21:18+05:30 colima containerd[1497]: time="2026-10-07T23:21:18.998653007+05:30" level=info msg="cleaning up after shim disconnected" id=7d7718cfd6a32f547ee7f03e7bbad955069673f47bc049bb5f7d70305927e45b namespace=moby
2026-10-07T23:21:18+05:30 colima containerd[1497]: time="2026-10-07T23:21:18.998691794+05:30" level=info msg="cleaning up dead shim" id=7d7718cfd6a32f547ee7f03e7bbad955069673f47bc049bb5f7d70305927e45b namespace=moby
2026-10-07T23:21:19+05:30 colima containerd[1497]: time="2026-10-07T23:21:19.144940594+05:30" level=info msg="connecting to shim e8ba8cc301c492d2588b350c74891a63ef4c111f2db99b46f851568e61222807" address="unix:///run/containerd/s/77f84181cd939a3a884d9b69ab83a6ca6a62c5e4ff8dfe1b7d126003cbdca4d3" namespace=moby protocol=ttrpc version=3
$ colima ssh -- journalctl -u ssh -n 5 --no-pager
Oct 07 23:04:36 lima-colima sshd[1251]: Accepted publickey for vanshsrivastava from 192.168.5.2 port 23321 ssh2: ED25519 SHA256:TIr9glZmLV1JxD5hEaCLbaK44M6dzNX70HbDBWKB26M
Oct 07 23:04:36 lima-colima sshd[1251]: pam_unix(sshd:session): session opened for user vanshsrivastava(uid=501) by vanshsrivastava(uid=0)
Oct 07 23:04:36 lima-colima sshd[1251]: pam_unix(sshd:session): session closed for user vanshsrivastava
Oct 07 23:04:36 lima-colima sshd[1269]: Accepted publickey for vanshsrivastava from 192.168.5.2 port 24546 ssh2: ED25519 SHA256:TIr9glZmLV1JxD5hEaCLbaK44M6dzNX70HbDBWKB26M
Oct 07 23:04:36 lima-colima sshd[1269]: pam_unix(sshd:session): session opened for user vanshsrivastava(uid=501) by vanshsrivastava(uid=0)
$ colima ssh -- journalctl -u ssh --since today --grep "Accepted" --no-pager | tail -3
Oct 07 23:04:36 lima-colima sshd[1221]: Accepted publickey for vanshsrivastava from 192.168.5.2 port 23761 ssh2: ED25519 SHA256:TIr9glZmLV1JxD5hEaCLbaK44M6dzNX70HbDBWKB26M
Oct 07 23:04:36 lima-colima sshd[1251]: Accepted publickey for vanshsrivastava from 192.168.5.2 port 23321 ssh2: ED25519 SHA256:TIr9glZmLV1JxD5hEaCLbaK44M6dzNX70HbDBWKB26M
Oct 07 23:04:36 lima-colima sshd[1269]: Accepted publickey for vanshsrivastava from 192.168.5.2 port 24546 ssh2: ED25519 SHA256:TIr9glZmLV1JxD5hEaCLbaK44M6dzNX70HbDBWKB26M
$ colima ssh -- journalctl -u docker -u containerd -r -n 4 --no-pager
Oct 07 23:21:46 colima dockerd[1578]: time="2026-10-07T23:21:46.906995872+05:30" level=info msg="image pulled" digest="sha256:5291449c3df73caf6ed85e649dec1b9e818b39a5d8c871e97afc13e9cd5e8fa8" remote="public.ecr.aws/docker/library/alpine:3.22"
Oct 07 23:21:19 colima dockerd[1578]: time="2026-10-07T23:21:19.201119952+05:30" level=info msg="sbJoin: gwep4 ''->'20ba501b3f86', gwep6 ''->''" eid=20ba501b3f86 ep=s20-cadvisor net=s20-monitoring-net nid=0a4836d4c640 spanID=f0db29fb026a9bb7 traceID=1cf0a070ddb2b015ad5bf7f4f6fc3910
Oct 07 23:21:19 colima containerd[1497]: time="2026-10-07T23:21:19.144940594+05:30" level=info msg="connecting to shim e8ba8cc301c492d2588b350c74891a63ef4c111f2db99b46f851568e61222807" address="unix:///run/containerd/s/77f84181cd939a3a884d9b69ab83a6ca6a62c5e4ff8dfe1b7d126003cbdca4d3" namespace=moby protocol=ttrpc version=3
Oct 07 23:21:19 colima dockerd[1578]: time="2026-10-07T23:21:19.133586902+05:30" level=warning msg="path in container /dev/kmsg already exists in privileged mode" container=e8ba8cc301c492d2588b350c74891a63ef4c111f2db99b46f851568e61222807 spanID=f0db29fb026a9bb7 traceID=1cf0a070ddb2b015ad5bf7f4f6fc3910
```

- `-o short-iso` prints ISO timestamps with the time zone.
- The `ssh` unit shows the logins that Colima makes into the VM (`Accepted publickey` from the host side, 192.168.5.2).
- `--grep "Accepted"` filters by message text inside journalctl.
- Two `-u` flags merge both services, and `-r` puts the newest line first.

### Output formats

```bash
$ colima ssh -- journalctl -u ssh -n 1 -o json-pretty --no-pager
{
	"SYSLOG_IDENTIFIER" : "sshd",
	"_CAP_EFFECTIVE" : "1ffffffffff",
	"_SYSTEMD_UNIT" : "ssh.service",
	"SYSLOG_PID" : "1269",
	"_MACHINE_ID" : "2257a37d7dc6468ab90b6f37c632a9c8",
	"_TRANSPORT" : "syslog",
	"_HOSTNAME" : "lima-colima",
	"__REALTIME_TIMESTAMP" : "1791394476699979",
	"__MONOTONIC_TIMESTAMP" : "5259615",
	"_SYSTEMD_CGROUP" : "/system.slice/ssh.service",
	"_SOURCE_REALTIME_TIMESTAMP" : "1791394476699964",
	"_COMM" : "sshd",
	"PRIORITY" : "6",
	"MESSAGE" : "pam_unix(sshd:session): session opened for user vanshsrivastava(uid=501) by vanshsrivastava(uid=0)",
	"__CURSOR" : "s=c508ce63ba4247edb8a1b0d3957d9061;i=727;b=4a59c6dd58b34c6e8486fc57556add43;m=50415f;t=65d43876fb14b;x=860f5acf3ac8e19",
	"_BOOT_ID" : "4a59c6dd58b34c6e8486fc57556add43",
	"_RUNTIME_SCOPE" : "system",
	"_EXE" : "/usr/sbin/sshd",
	"_CMDLINE" : "\"sshd: vanshsrivastava [priv]\"",
	"__SEQNUM" : "1831",
	"_UID" : "0",
	"_SYSTEMD_SLICE" : "system.slice",
	"SYSLOG_FACILITY" : "10",
	"__SEQNUM_ID" : "c508ce63ba4247edb8a1b0d3957d9061",
	"_SELINUX_CONTEXT" : "unconfined\n",
	"_PID" : "1269",
	"_GID" : "0",
	"SYSLOG_TIMESTAMP" : "Oct  7 23:04:36 ",
	"_SYSTEMD_INVOCATION_ID" : "bba19ce302054b15ae768064c513cc54"
}
$ colima ssh -- journalctl -u ssh -n 3 -o cat --no-pager
pam_unix(sshd:session): session closed for user vanshsrivastava
Accepted publickey for vanshsrivastava from 192.168.5.2 port 24546 ssh2: ED25519 SHA256:TIr9glZmLV1JxD5hEaCLbaK44M6dzNX70HbDBWKB26M
pam_unix(sshd:session): session opened for user vanshsrivastava(uid=501) by vanshsrivastava(uid=0)
```

`-o json-pretty` shows every field journald stores for one entry (`_SYSTEMD_UNIT`, `_PID`, `PRIORITY`, `_BOOT_ID`, ...). These fields are what `-u`, `-p` and `-b` filter on, and the same fields can be used directly, for example `journalctl _PID=1269` or `journalctl _COMM=sshd`. `-o cat` prints only the message text. The ssh entry here has `PRIORITY` 6 because sshd sends a real syslog priority.

### Follow logs live

While `journalctl -f` was following the Docker unit, the script started and removed a tiny container called `s01-journal-demo` in the background:

```bash
$ colima ssh -- timeout 10 journalctl -u docker -f -n 0 --no-pager
Oct 07 23:21:49 colima dockerd[1578]: time="2026-10-07T23:21:49.365981054+05:30" level=info msg="sbJoin: gwep4 ''->'b3dded1e14a7', gwep6 ''->''" eid=b3dded1e14a7 ep=s16-pytest net=bridge nid=ee27389cf7a0
Oct 07 23:21:50 colima dockerd[1578]: time="2026-10-07T23:21:50.749605467+05:30" level=info msg="sbJoin: gwep4 ''->'5a2a29fc5579', gwep6 ''->''" eid=5a2a29fc5579 ep=s01-journal-demo net=bridge nid=ee27389cf7a0
Oct 07 23:21:50 colima dockerd[1578]: time="2026-10-07T23:21:50.765284342+05:30" level=info msg="received task-delete event from containerd" container=87c51a5bf8c8d39984cc8ad04396bf856679dbb3a5f34245e9eb2311e120786b module=libcontainerd namespace=moby topic=/tasks/delete type="*events.TaskDelete"
Oct 07 23:21:56 colima dockerd[1578]: time="2026-10-07T23:21:56.800043275+05:30" level=info msg="sbJoin: gwep4 ''->'08266c57db7f', gwep6 ''->''" eid=08266c57db7f ep=final-pytest net=bridge nid=ee27389cf7a0
time="2026-10-07T23:21:57+05:30" level=fatal msg="exit status 124"
```

The `ep=s01-journal-demo` line appeared live, together with lines from other containers being started on the same Docker engine. Without `timeout` this would run until Ctrl+C. The last line is printed by `colima ssh` on the Mac: `timeout` ends `journalctl` with exit code 124, and Colima reports the non-zero exit code.

## Task 4: Linux Command Cheat Sheet

I reviewed the two cheat sheets in the course repo (`session2-linux/basic-linux.pdf` and `session2-linux/ad-linux.pdf`, plus the networking one, which I used in Session 04) and ran the commands in `practice/task4-cheatsheet.sh`. Purpose and basic usage of each:

| Area | Command | Purpose | Example |
|---|---|---|---|
| Files | `ls`, `cd`, `pwd` | list, change, print directory | `ls -l /etc` |
| Files | `mkdir`, `touch`, `cp`, `mv`, `rm` | create dir, create empty file, copy, move/rename, delete | `rm -rf /tmp/devops_logs` |
| View | `cat`, `head`, `tail`, `less`, `more` | print a file, first/last lines, page through a file | `tail -n 100 /var/log/syslog` |
| Search | `grep`, `find`, `locate` | search inside files, search for files | `grep ERROR /var/log/syslog` |
| Processes | `ps`, `top`, `htop` | list processes, live view | `ps aux` |
| Processes | `kill`, `pkill`, `nice`, `renice`, `nohup`, `bg`/`fg` | stop processes, priorities, keep running after logout, job control | `kill -9 1234` |
| Services | `systemctl status/restart` | manage systemd services | `systemctl status nginx` |
| Network | `ping`, `ip a`/`ifconfig`, `netstat`/`ss`, `curl`, `wget`, `lsof -i` | connectivity, addresses, open ports, HTTP | `netstat -tulnp` |
| Permissions | `chmod`, `chown`, `umask` | mode bits, owner, default mask | `chmod 755 script.sh` |
| Packages | `apt` (Ubuntu/Debian), `yum`/`dnf` (RHEL/CentOS) | install software | `apt update && apt install nginx -y` |
| Disk | `df`, `du`, `free`, `lsblk`, `mount` | filesystem usage, folder size, memory, block devices | `df -h`, `du -sh /var/log` |
| Scheduling | `crontab`, `nohup ... &` | scheduled jobs, background jobs | `0 2 * * * /home/user/backup.sh` |
| Users | `adduser`, `useradd`, `usermod`, `passwd`, `id`, `groups`, `who`, `w`, `last` | manage and inspect users | `usermod -aG sudo devops` |
| System | `uname -a`, `hostname`, `uptime`, `whoami`, `date`, `history` | system information | `uname -a` |
| Monitoring | `vmstat`, `free -h`, `uptime` | CPU, memory, load | `vmstat 1` |
| Debugging | `journalctl -xe`, `tail -f`, `dmesg`, `file`, `xargs`, `alias` | logs and handy tools | `alias ll='ls -alF'` |

### Files and directories

```bash
$ ls -l /etc | head -5
total 484
-rw-r--r-- 1 root root    3444 Jul  5  2023 adduser.conf
drwxr-xr-x 1 root root    4096 Oct  7 17:53 alternatives
drwxr-xr-x 3 root root    4096 Oct  7 17:53 apparmor.d
drwxr-xr-x 8 root root    4096 Sep 17 02:10 apt
$ cd /var/log && pwd
/var/log
$ mkdir /tmp/devops_logs && cd /tmp/devops_logs && pwd
/tmp/devops_logs
$ touch index.html
$ cp index.html index-copy.html
$ mv index-copy.html backup_index.html
$ ls -l
total 0
-rw-r--r-- 1 root root 0 Oct  7 17:54 backup_index.html
-rw-r--r-- 1 root root 0 Oct  7 17:54 index.html
$ cd / && rm -rf /tmp/devops_logs && ls -d /tmp/devops_logs
ls: cannot access '/tmp/devops_logs': No such file or directory
```

### Viewing and searching files

```bash
$ cat /etc/os-release
PRETTY_NAME="Ubuntu 24.04.5 LTS"
NAME="Ubuntu"
VERSION_ID="24.04"
VERSION="24.04.5 LTS (Noble Numbat)"
VERSION_CODENAME=noble
ID=ubuntu
ID_LIKE=debian
HOME_URL="https://www.ubuntu.com/"
SUPPORT_URL="https://help.ubuntu.com/"
BUG_REPORT_URL="https://bugs.launchpad.net/ubuntu/"
PRIVACY_POLICY_URL="https://www.ubuntu.com/legal/terms-and-policies/privacy-policy"
UBUNTU_CODENAME=noble
LOGO=ubuntu-logo
$ head -n 3 /etc/passwd
root:x:0:0:root:/root:/bin/bash
daemon:x:1:1:daemon:/usr/sbin:/usr/sbin/nologin
bin:x:2:2:bin:/bin:/usr/sbin/nologin
$ tail -n 3 /etc/passwd
ubuntu:x:1000:1000:Ubuntu:/home/ubuntu:/bin/bash
systemd-network:x:998:998:systemd Network Management:/:/usr/sbin/nologin
tcpdump:x:100:102::/nonexistent:/usr/sbin/nologin
$ grep -n "^root" /etc/passwd
1:root:x:0:0:root:/root:/bin/bash
$ grep -c "nologin" /etc/passwd
18
$ tail -n 3 /var/log/dpkg.log
2026-10-07 17:53:48 trigproc ca-certificates:all 20260601~24.04.1 <none>
2026-10-07 17:53:48 status half-configured ca-certificates:all 20260601~24.04.1
2026-10-07 17:53:48 status installed ca-certificates:all 20260601~24.04.1
$ grep -c " install " /var/log/dpkg.log
168
$ grep -ic "error" /var/log/dpkg.log
25
$ grep -i "error" /var/log/dpkg.log | head -2
2026-09-17 02:10:18 install libgpg-error0:arm64 <none> 1.47-3build2
2026-09-17 02:10:18 status half-installed libgpg-error0:arm64 1.47-3build2
$ grep -iw "error" /var/log/dpkg.log || echo "no line contains the whole word error"
no line contains the whole word error
```

`grep -c` counts matching lines. `grep -ic error` found 25 lines, but they are all the package name `libgpg-error0`, not real errors; `-w` matches the whole word only, and then nothing matches. Good reminder to search logs carefully.

### Processes

```bash
$ ps
    PID TTY          TIME CMD
      1 ?        00:00:00 docker-init
      7 ?        00:00:00 sleep
   3381 ?        00:00:00 timeout
   3387 ?        00:00:00 bash
   3409 ?        00:00:00 ps
$ ps aux | head -5
USER         PID %CPU %MEM    VSZ   RSS TTY      STAT START   TIME COMMAND
root           1  0.0  0.0    872   564 ?        Ss   17:53   0:00 /sbin/docker-init -- sleep infinity
root           7  0.0  0.0   2268  1204 ?        S    17:53   0:00 sleep infinity
root        3381  0.0  0.0   2276  1352 ?        Ss   17:54   0:00 timeout 300 bash /root/practice/task4-cheatsheet.sh
root        3387  0.0  0.0   4032  3064 ?        S    17:54   0:00 bash /root/practice/task4-cheatsheet.sh
$ top -b -n 1 | head -10
top - 17:54:17 up 19 min,  0 user,  load average: 3.68, 2.14, 1.04
Tasks:   6 total,   1 running,   5 sleeping,   0 stopped,   0 zombie
%Cpu(s): 16.9 us, 11.9 sy,  0.0 ni, 67.8 id,  1.7 wa,  0.0 hi,  1.7 si,  0.0 st 
MiB Mem :   9921.8 total,    399.5 free,   2994.6 used,   6783.4 buff/cache     
MiB Swap:      0.0 total,      0.0 free,      0.0 used.   6927.3 avail Mem 

    PID USER      PR  NI    VIRT    RES    SHR S  %CPU  %MEM     TIME+ COMMAND
      1 root      20   0     872    564    516 S   0.0   0.0   0:00.01 docker-+
      7 root      20   0    2268   1204   1124 S   0.0   0.0   0:00.00 sleep
   3381 root      20   0    2276   1352   1272 S   0.0   0.0   0:00.00 timeout
$ sleep 301 & echo "started PID $!"
started PID 3414
$ nice -n 10 sleep 302 & echo "started PID $!"
started PID 3415
$ nohup sleep 303 > /tmp/nohup.out 2>&1 & echo "started PID $!"
started PID 3416
$ pgrep -a sleep
7 sleep infinity
3414 sleep 301
3415 sleep 302
3416 sleep 303
$ ps -o pid,ni,cmd -p "$(pgrep -f "sleep 302")"
    PID  NI CMD
   3415  10 sleep 302
$ renice -n 15 -p "$(pgrep -f "sleep 302")"
3415 (process ID) old priority 10, new priority 15
$ kill -9 "$(pgrep -f "sleep 301")"
$ pkill -f "sleep 30[23]"
/root/practice/lib.sh: line 10:  3414 Killed                  sleep 301
$ sleep 0.5; pgrep -a sleep
7 sleep infinity
```

- `ps` and `ps aux` list processes; `top -b -n 1` is one snapshot of `top` in batch mode (normal `top`/`htop` are interactive).
- `nice -n 10` started a process with lower priority (NI 10), `renice` changed it to 15 while it was running.
- `kill -9 PID` killed one process by PID, `pkill -f` killed by matching the command line. The `Killed sleep 301` line is bash reporting the job that `kill -9` ended. Only `sleep infinity` (the container's main process) is left.

### Permissions and ownership

```bash
$ cd /tmp && echo "echo hello from script" > script.sh && ls -l script.sh
-rw-r--r-- 1 root root 23 Oct  7 17:54 script.sh
$ ./script.sh
/root/practice/lib.sh: line 10: ./script.sh: Permission denied
$ chmod 755 script.sh && ls -l script.sh
-rwxr-xr-x 1 root root 23 Oct  7 17:54 script.sh
$ ./script.sh
hello from script
$ chmod u=rw,go= script.sh && stat -c "%a %A %n" script.sh
600 -rw------- script.sh
$ chown ubuntu:ubuntu script.sh && ls -l script.sh
-rw------- 1 ubuntu ubuntu 23 Oct  7 17:54 script.sh
$ umask
0022
$ rm /tmp/script.sh
```

A new file gets `644` (`rw-r--r--`) because `umask` is `0022`, so it cannot be executed until `chmod 755`. `chmod u=rw,go=` is the symbolic form of `600`.

### Package management

```bash
$ apt-get update 2>&1 | tail -2
Hit:4 http://ports.ubuntu.com/ubuntu-ports noble-security InRelease
Reading package lists...
$ apt-get install -y htop 2>&1 | grep -E "^(The following NEW|  htop|Setting up)"
The following NEW packages will be installed:
  htop libnl-genl-3-200
Setting up libnl-genl-3-200:arm64 (3.7.0-0.3build1.1) ...
Setting up htop (3.3.0-4build1) ...
$ htop --version
htop 3.3.0
$ command -v yum || echo "yum: not available on Ubuntu (RHEL/CentOS use yum or dnf)"
yum: not available on Ubuntu (RHEL/CentOS use yum or dnf)
```

`htop` is not installed by default (the cheat sheet says so too), so I installed it with apt. I did not open it because it is a full-screen interactive tool.

### Disk and storage

```bash
$ df -h
Filesystem      Size  Used Avail Use% Mounted on
overlay          59G   27G   29G  49% /
tmpfs            64M     0   64M   0% /dev
shm              64M     0   64M   0% /dev/shm
/dev/root        19G  870M   18G   5% /usr/sbin/docker-init
/dev/vdb1        59G   27G   29G  49% /etc/hosts
tmpfs           4.9G     0  4.9G   0% /proc/acpi
tmpfs           4.9G     0  4.9G   0% /proc/scsi
tmpfs           4.9G     0  4.9G   0% /sys/firmware
$ du -sh /var/log
380K	/var/log
$ du -sh /usr/* 2>/dev/null | sort -h | tail -4
12M	/usr/sbin
32M	/usr/share
38M	/usr/bin
167M	/usr/lib
$ free -h
               total        used        free      shared  buff/cache   available
Mem:           9.7Gi       2.9Gi       430Mi        25Mi       6.6Gi       6.8Gi
Swap:             0B          0B          0B
$ lsblk
NAME    MAJ:MIN RM  SIZE RO TYPE MOUNTPOINTS
vda     253:0    0   20G  0 disk 
|-vda1  253:1    0   19G  0 part /usr/sbin/docker-init
|-vda15 253:15   0   99M  0 part 
`-vda16 259:0    0  923M  0 part 
vdb     253:16   0   60G  0 disk 
`-vdb1  253:17   0   60G  0 part /etc/hosts
                                 /etc/hostname
                                 /etc/resolv.conf
vdc     253:32   0 19.1M  1 disk 
$ findmnt --target / -o TARGET,SOURCE,FSTYPE
TARGET SOURCE  FSTYPE
/      overlay overlay
```

Inside a container `/` is an `overlay` filesystem. `lsblk` shows the disks of the Colima VM underneath, and `/etc/hosts`, `/etc/hostname`, `/etc/resolv.conf` are files that Docker bind-mounts into the container.

### Scheduling

```bash
$ echo "0 2 * * * /home/user/backup.sh" | crontab -
$ crontab -l
0 2 * * * /home/user/backup.sh
$ crontab -r && crontab -l
no crontab for root
```

`crontab -e` opens an editor; piping a line into `crontab -` installs the same entry without the editor. `0 2 * * *` means 02:00 every day. The `nohup` example is in the Processes block above.

### Users

```bash
$ whoami
root
$ id
uid=0(root) gid=0(root) groups=0(root)
$ groups
root
$ who; echo "who exit code: $?"
who exit code: 0
$ w
 17:54:21 up 19 min,  0 user,  load average: 3.63, 2.15, 1.05
USER     TTY      FROM             LOGIN@   IDLE   JCPU   PCPU  WHAT
$ last | head -3

wtmp begins Wed Oct  7 17:44:22 2026
```

`who` and `w` print no users because nobody logged in to the container through a terminal (`docker exec` is not a login), and `last` has an empty login history. The user-management commands (`adduser`, `useradd`, `usermod`, `passwd`, `id`, `groups`, `deluser`, `userdel`) are in Task 2.

### System information

```bash
$ uname -a
Linux s01-ubuntu 6.8.0-117-generic #117-Ubuntu SMP PREEMPT_DYNAMIC Thu May  7 17:26:37 UTC 2026 aarch64 aarch64 aarch64 GNU/Linux
$ hostname
s01-ubuntu
$ uptime
 17:54:21 up 19 min,  0 user,  load average: 3.63, 2.15, 1.05
$ date
Wed Oct  7 17:54:21 UTC 2026
$ printf "set -o history\necho one > /dev/null\necho two > /dev/null\nhistory\n" | bash
    1  echo one > /dev/null
    2  echo two > /dev/null
    3  history
```

`uname -a` shows the Colima VM's kernel, because containers share the host kernel. `history` only records commands in a shell that has history turned on, so I enabled it with `set -o history` in a child bash.

### Advanced and troubleshooting commands

```bash
$ vmstat 1 3
procs -----------memory---------- ---swap-- -----io---- -system-- -------cpu-------
 r  b   swpd   free   buff  cache   si   so    bi    bo   in   cs us sy id wa st gu
 1  0      0 441148 512296 6438212    0    0  2358 26900 15178   42  6  4 89  1  0  0
 1  0      0 455708 512296 6438980    0    0     0    24 25952 42724  9  6 85  0  0  0
 1  0      0 478052 512304 6439264    0    0     0   160 25467 42005  9  6 85  0  0  0
$ ss -tulwn
Netid State Recv-Q Send-Q Local Address:Port Peer Address:PortProcess
$ nc -l 80 > /dev/null & sleep 1; echo "nc listening, PID $!"
nc listening, PID 3626
$ ss -tulwn
Netid State  Recv-Q Send-Q Local Address:Port Peer Address:PortProcess
tcp   LISTEN 0      1            0.0.0.0:80        0.0.0.0:*          
$ ss -plnt
State  Recv-Q Send-Q Local Address:Port Peer Address:PortProcess
LISTEN 0      1            0.0.0.0:80        0.0.0.0:*    users:(("nc",pid=3626,fd=3))
$ netstat -tulnp
Active Internet connections (only servers)
Proto Recv-Q Send-Q Local Address           Foreign Address         State       PID/Program name    
tcp        0      0 0.0.0.0:80              0.0.0.0:*               LISTEN      3626/nc             
$ lsof -i :80
COMMAND  PID USER   FD   TYPE DEVICE SIZE/OFF NODE NAME
nc      3626 root    3u  IPv4 430153      0t0  TCP *:http (LISTEN)
$ pkill -x nc; sleep 0.5; ss -tln
State Recv-Q Send-Q Local Address:Port Peer Address:PortProcess
$ find / -type f -name "os-release" 2>/dev/null
/usr/lib/os-release
$ file /bin/ls /etc/passwd
/bin/ls:     ELF 64-bit LSB pie executable, ARM aarch64, version 1 (SYSV), dynamically linked, interpreter /lib/ld-linux-aarch64.so.1, BuildID[sha1]=00a639537eef557c0dcb20ad52892bc84863ed94, for GNU/Linux 3.7.0, stripped
/etc/passwd: ASCII text
$ mkdir -p /tmp/xdemo && touch /tmp/xdemo/a.log /tmp/xdemo/b.log /tmp/xdemo/keep.txt
$ find /tmp/xdemo -name "*.log" | xargs rm -v
removed '/tmp/xdemo/b.log'
removed '/tmp/xdemo/a.log'
$ ls /tmp/xdemo && rm -r /tmp/xdemo
keep.txt
$ shopt -s expand_aliases; alias ll="ls -alF"; alias ll
alias ll='ls -alF'
$ ll -d /tmp
drwxrwxrwt 1 root root 4096 Oct  7 17:54 /tmp/
$ ls -ltr /var/log | tail -3
-rw-r--r--  1 root root              7504 Oct  7 17:53 alternatives.log
drwxr-xr-x  1 root root              4096 Oct  7 17:54 apt
-rw-r--r--  1 root root            228232 Oct  7 17:54 dpkg.log
$ dmesg | tail -2
dmesg: read kernel buffer failed: Operation not permitted
$ echo "first line" > /tmp/app.log; ( sleep 1; echo "line written while tail -f was watching" >> /tmp/app.log ) & timeout 3 tail -f /tmp/app.log; echo "timeout stopped tail -f (exit code $?)"
first line
line written while tail -f was watching
timeout stopped tail -f (exit code 124)
$ rm /tmp/app.log /tmp/nohup.out
```

- `vmstat 1 3` prints CPU, memory and I/O every second, three times.
- `ss -tulwn` was empty at first (nothing listening). After starting `nc -l 80`, `ss`, `netstat -tulnp` and `lsof -i :80` all show the listener and the process that owns it. `ss` is the modern replacement for `netstat`.
- `find ... | xargs rm -v` deleted only the `.log` files.
- `dmesg` is not allowed in an unprivileged container (no `CAP_SYSLOG`); on the VM, `journalctl -k` from Task 3 shows the kernel log instead.
- `tail -f` printed the line that was appended while it was watching; `timeout` stopped it after 3 seconds (exit code 124).

### Commands from the cheat sheets I did not run here

- `less`, `more`, `htop`, `crontab -e`, `sudo visudo`: interactive full-screen tools; there is no terminal in `docker exec` without `-it`.
- `systemctl status/restart nginx`: the container has no systemd. I used `systemctl status docker` on the Colima VM in Task 3 instead (read-only).
- `!!`, `!n`, `Ctrl+C`, `Ctrl+L`, `bg`, `fg`, `clear`: only meaningful in an interactive terminal.
- `yum install`: RHEL/CentOS only (shown above as not found on Ubuntu).
- `iostat`, `sar` (need `sysstat`), `strace`, `nmap`, `tldr`, `locate`: not installed in the minimal image. `ssh`, `scp`, `rsync` need a second host. `mount`/`umount` of real devices is not allowed in an unprivileged container.

## What I learned

- A file name points to an inode. Hard links are extra names for the same inode, soft links are files that store a path. That one idea explains every behaviour above (deleting, recreating, directories, cross-filesystem).
- On Ubuntu I should use `adduser` for people and keep `useradd -m -s /bin/bash` for scripts; plain `useradd` creates a user with no home, `/bin/sh` and a locked password.
- `journalctl -u <service>` with `--since`, `-f` and `--grep` is the quickest way to read a service's logs, but `-p` only works when the program sends a real priority; Docker's `level=error` text is stored as info.
- Containers are not full Linux machines: no systemd, no `adduser` in the minimal image, no `dmesg`, and `ping` results can be misleading (see Session 04). Knowing where a command runs matters.
- `grep` matches substrings, so `grep -w` or a more specific pattern avoids false matches like `libgpg-error0`.
