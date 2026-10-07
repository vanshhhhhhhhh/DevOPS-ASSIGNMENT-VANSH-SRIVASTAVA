# Session 03: Shell Scripting

**Name:** Vansh Srivastava
**Enrollment No.:** 24bcs10567
**Session:** 03

Session 03 covered bash scripting basics from the course repo: variables, `read -p` for input, `if`/`elif`, `for` and `while` loops, functions, and `>` / `>>` redirection. For the homework I wrote `system_info.sh`, a System Information Script that prints the date, hostname, user, disk usage and running processes, takes input with `read -p`, creates a directory and a file, and saves the process list into the file with `>`. I ran it for real on macOS and on Ubuntu Linux.

## Folder structure

```text
session-03-shell-scripting/
├── README.md          # this file: how the script works and the real output
├── system_info.sh     # the System Information Script (the submission)
└── .gitignore         # ignores the report folders the script creates when run here
```

## Environment

- macOS 26.6.2 on Apple Silicon, `/bin/bash` 3.2.57 (the old bash that ships with macOS).
- Ubuntu 24.04.5 in a throwaway Docker container (`s01-ubuntu`, run through Colima), bash 5.2.21.

## Task: System Information Script

### Requirements and where they are in the script

| Requirement | How `system_info.sh` does it |
|---|---|
| print the current date | `CURRENT_DATE=$(date)` then `echo "Date     : $CURRENT_DATE"` |
| print the hostname | `HOST_NAME=$(hostname)` |
| print the username | `USER_NAME=$(whoami)` |
| print the disk usage | `df -h` |
| print the running processes | `ps -e` for the count, `ps -eo pid,user,%cpu,%mem,comm` sorted by CPU for the top 10 |
| use variables | `CURRENT_DATE`, `HOST_NAME`, `USER_NAME`, `OS_NAME`, `LINE`, `PS_COLUMNS`, `NAME`, `REPORT_DIR`, `PROCESS_FILE`, `PROCESS_COUNT` |
| take user input with `read -p` | `read -r -p "Enter your name: " NAME` and `read -r -p "Enter a directory name ..." REPORT_DIR` |
| create a directory with `mkdir` | `mkdir -p "$REPORT_DIR"` |
| create a file with `touch` | `touch "$PROCESS_FILE"` |
| store the processes in the file with `>` | `ps -eo user,pid,ppid,%cpu,%mem,stat,time,comm > "$PROCESS_FILE"` |

### The script

```bash
#!/usr/bin/env bash
#
# system_info.sh - Session 03 homework: System Information Script
# Author: Vansh Srivastava (24bcs10567)
#
# Prints the date, hostname, username, disk usage and running processes,
# asks the user for a name and a directory with read -p, creates that
# directory with mkdir, creates a file with touch and saves the running
# processes into it with > output redirection.
#
# Works with bash on Linux (GNU tools) and on macOS (BSD tools, bash 3.2),
# so it only uses options that both versions of ps and df understand.
#
# Usage:  ./system_info.sh
#         printf 'Vansh\nmy_report\n' | ./system_info.sh   (answers from a pipe)

# ---------- variables ----------
CURRENT_DATE=$(date)
HOST_NAME=$(hostname)
USER_NAME=$(whoami)
OS_NAME=$(uname -s)
LINE="--------------------------------------------------"
PS_COLUMNS="pid,user,%cpu,%mem,comm"   # same column names on Linux and macOS

echo "$LINE"
echo "  System Information Report"
echo "$LINE"
echo "Date     : $CURRENT_DATE"
echo "Hostname : $HOST_NAME"
echo "Username : $USER_NAME"
echo "OS       : $OS_NAME"

# ---------- user input (read -p; -r keeps any backslash exactly as typed) ----------
read -r -p "Enter your name: " NAME
read -r -p "Enter a directory name for the report [sysinfo_report]: " REPORT_DIR

NAME=${NAME:-unknown}
REPORT_DIR=${REPORT_DIR:-sysinfo_report}   # default if the user just presses Enter
PROCESS_FILE="$REPORT_DIR/processes.txt"

echo "Name entered      : $NAME"
echo "Report directory  : $REPORT_DIR"

# ---------- disk usage ----------
echo "$LINE"
echo "Disk usage (df -h):"
df -h

# ---------- running processes ----------
PROCESS_COUNT=$(ps -e | tail -n +2 | wc -l | tr -d ' ')
echo "$LINE"
echo "Running processes: $PROCESS_COUNT in total. Top 10 by CPU:"
ps -eo "$PS_COLUMNS" | head -n 1
ps -eo "$PS_COLUMNS" | tail -n +2 | sort -k3 -nr | head -n 10

# ---------- mkdir, touch and > redirection ----------
mkdir -p "$REPORT_DIR"
touch "$PROCESS_FILE"
ps -eo user,pid,ppid,%cpu,%mem,stat,time,comm > "$PROCESS_FILE"

echo "$LINE"
echo "Created directory : $REPORT_DIR"
echo "Created file      : $PROCESS_FILE ($(wc -l < "$PROCESS_FILE" | tr -d ' ') lines)"
echo "Thank you, $NAME. Report finished at $(date)."
```

Notes on the choices I made:

- `#!/usr/bin/env bash`: `read -p` is a bash feature (plain `sh` on Ubuntu is `dash`, which does not have `-p`), so the script must run with bash. `env` finds bash wherever it is installed.
- `read -r -p`: `-p` shows the prompt, `-r` keeps a backslash in the answer as typed (ShellCheck recommends it).
- `${REPORT_DIR:-sysinfo_report}` gives a default when the user just presses Enter.
- Portability: GNU `ps` (Linux) and BSD `ps` (macOS) have different sort options (`--sort` vs `-r`), so I print fixed columns with `ps -eo` and sort with `sort -k3 -nr` (third column, `%CPU`, numeric, highest first). Both systems understand that.
- `mkdir -p` does not fail if the directory already exists, so the script can be run twice.
- For the file I save fixed columns ending with `comm` (the program name) instead of `ps aux`. `ps aux` would also save every process's full command line, and command lines can contain things like tokens or passwords passed as arguments, which should not end up in a report file.
- Every variable is quoted (`"$REPORT_DIR"`) so names with spaces work.

### How I ran it

To keep the repo clean I copied the script into an empty working directory on each system and ran it there. The brief asks for real `read -p` input, so I fed the two answers through a pipe (macOS) and a heredoc (Linux). Both are standard input for `read`, exactly like typing them.

### Run 1: macOS (bash 3.2, answers from a pipe)

```bash
$ bash --version | head -1
GNU bash, version 3.2.57(1)-release (arm64-apple-darwin25)
$ ls
system_info.sh
$ printf 'Vansh Srivastava\nmac_report\n' | ./system_info.sh
--------------------------------------------------
  System Information Report
--------------------------------------------------
Date     : Wed Oct  7 23:29:30 IST 2026
Hostname : whenoms-MacBook-Air.local
Username : vanshsrivastava
OS       : Darwin
Name entered      : Vansh Srivastava
Report directory  : mac_report
--------------------------------------------------
Disk usage (df -h):
Filesystem        Size    Used   Avail Capacity iused ifree %iused  Mounted on
/dev/disk3s1s1   460Gi    12Gi    45Gi    21%    459k  475M    0%   /
devfs            208Ki   208Ki     0Bi   100%     718     0  100%   /dev
/dev/disk3s6     460Gi   5.0Gi    45Gi    10%       5  475M    0%   /System/Volumes/VM
/dev/disk3s2     460Gi   8.4Gi    45Gi    16%    1.5k  475M    0%   /System/Volumes/Preboot
/dev/disk3s4     460Gi   2.3Mi    45Gi     1%      66  475M    0%   /System/Volumes/Update
/dev/disk1s2     500Mi   6.0Mi   481Mi     2%       1  4.9M    0%   /System/Volumes/xarts
/dev/disk1s1     500Mi   6.0Mi   481Mi     2%      32  4.9M    0%   /System/Volumes/iSCPreboot
/dev/disk1s3     500Mi   2.3Mi   481Mi     1%      94  4.9M    0%   /System/Volumes/Hardware
/dev/disk3s5     460Gi   389Gi    45Gi    90%    4.7M  475M    1%   /System/Volumes/Data
map auto_home      0Bi     0Bi     0Bi   100%       0     0     -   /System/Volumes/Data/home
/dev/disk5s1     2.1Gi   2.1Gi    72Mi    97%     438  741k    0%   /private/var/run/com.apple.security.cryptexd/mnt/com.apple.MobileAsset.MetalToolchain-v17.5.188.0.ReF2YC
--------------------------------------------------
Running processes: 611 in total. Top 10 by CPU:
  PID USER              %CPU %MEM COMM
 3836 vanshsrivastava   41.4 23.5 /System/Library/Frameworks/Virtualization.framework/Versions/A/XPCServices/com.apple.Virtualization.VirtualMachine.xpc/Contents/MacOS/com.apple.Virtualization.VirtualMachine
42924 root              37.0  0.2 /System/Library/PrivateFrameworks/XprotectFramework.framework/Versions/A/XPCServices/XprotectService.xpc/Contents/MacOS/XprotectService
  541 _driverkit         4.1  0.2 /System/Library/DriverExtensions/com.apple.DriverKit-AppleBCMWLAN.dext/com.apple.DriverKit-AppleBCMWLAN
99064 vanshsrivastava    3.5  1.8 /Users/vanshsrivastava/.vscode/extensions/anthropic.claude-code-2.1.291-darwin-arm64/resources/native-binary/claude
39386 _trustd            2.8  0.1 /usr/libexec/trustd
39254 vanshsrivastava    2.8  0.2 /System/Library/CoreServices/CoreServicesUIAgent.app/Contents/MacOS/CoreServicesUIAgent
  443 root               2.7  0.1 /usr/libexec/syspolicyd
  454 _mdnsresponder     1.9  0.1 /usr/sbin/mDNSResponder
  405 _windowserver      1.9  0.4 /System/Library/PrivateFrameworks/SkyLight.framework/Resources/WindowServer
 1866 vanshsrivastava    1.8  0.9 /Users/vanshsrivastava/.vscode/extensions/anthropic.claude-code-2.1.287-darwin-arm64/resources/native-binary/claude
--------------------------------------------------
Created directory : mac_report
Created file      : mac_report/processes.txt (608 lines)
Thank you, Vansh Srivastava. Report finished at Wed Oct  7 23:29:30 IST 2026.
```

Created directory and file:

```bash
$ ls -l mac_report
total 160
-rw-r--r--@ 1 vanshsrivastava  wheel  78777 Oct  7 23:29 processes.txt
$ head -n 5 mac_report/processes.txt
USER               PID  PPID  %CPU %MEM STAT      TIME COMM
root                 1     0   0.1  0.1 Ss    45:43.93 /sbin/launchd
root               332     1   0.0  0.1 Ss    15:31.78 /usr/libexec/logd
root               334     1   0.0  0.0 Ss     1:26.35 /usr/libexec/UserEventAgent
root               336     1   0.0  0.0 Ss    18:58.77 /System/Library/Frameworks/CoreServices.framework/Versions/A/Frameworks/FSEvents.framework/Versions/A/Support/fseventsd
$ wc -l mac_report/processes.txt
     608 mac_report/processes.txt
```

On the Mac the top CPU process is `com.apple.Virtualization.VirtualMachine`, which is the Colima VM that runs Docker. macOS `ps` prints the full path of each program in `comm`, and `df -h` also lists the system volumes of APFS.

### Run 2: Ubuntu 24.04 (bash 5.2, answers from a heredoc)

First a syntax check and ShellCheck (installed in the container with `apt-get install shellcheck`):

```bash
$ bash --version | head -1
GNU bash, version 5.2.21(1)-release (aarch64-unknown-linux-gnu)
$ ls -l
total 4
-rwxr-xr-x 1 501 dialout 2221 Oct  7 17:59 system_info.sh
$ bash -n system_info.sh && echo "syntax OK"
syntax OK
$ shellcheck system_info.sh && echo "shellcheck: no warnings"
shellcheck: no warnings
```

(The `501 dialout` owner is my Mac user ID, which `docker cp` kept when it copied the script into the container.)

```bash
$ ./system_info.sh <<EOF
Vansh Srivastava
linux_report
EOF
--------------------------------------------------
  System Information Report
--------------------------------------------------
Date     : Wed Oct  7 17:59:40 UTC 2026
Hostname : s01-ubuntu
Username : root
OS       : Linux
Name entered      : Vansh Srivastava
Report directory  : linux_report
--------------------------------------------------
Disk usage (df -h):
Filesystem      Size  Used Avail Use% Mounted on
overlay          59G   30G   27G  53% /
tmpfs            64M     0   64M   0% /dev
shm              64M     0   64M   0% /dev/shm
/dev/root        19G  874M   18G   5% /usr/sbin/docker-init
/dev/vdb1        59G   30G   27G  53% /etc/hosts
tmpfs           4.9G     0  4.9G   0% /proc/acpi
tmpfs           4.9G     0  4.9G   0% /proc/scsi
tmpfs           4.9G     0  4.9G   0% /sys/firmware
--------------------------------------------------
Running processes: 10 in total. Top 10 by CPU:
    PID USER     %CPU %MEM COMMAND
   3749 root      0.0  0.0 head
   3748 root      0.0  0.0 sort
   3747 root      0.0  0.0 tail
   3746 root      0.0  0.0 ps
   3733 root      0.0  0.0 bash
   3727 root      0.0  0.0 bash
   3721 root      0.0  0.0 timeout
      7 root      0.0  0.0 sleep
      1 root      0.0  0.0 docker-init
--------------------------------------------------
Created directory : linux_report
Created file      : linux_report/processes.txt (7 lines)
Thank you, Vansh Srivastava. Report finished at Wed Oct  7 17:59:40 UTC 2026.
```

Created directory and file:

```bash
$ ls -l
total 8
drwxr-xr-x 2 root root    4096 Oct  7 17:59 linux_report
-rwxr-xr-x 1  501 dialout 2221 Oct  7 17:59 system_info.sh
$ ls -l linux_report
total 4
-rw-r--r-- 1 root root 390 Oct  7 17:59 processes.txt
$ head -n 8 linux_report/processes.txt
USER         PID    PPID %CPU %MEM STAT     TIME COMMAND
root           1       0  0.0  0.0 Ss   00:00:00 docker-init
root           7       1  0.0  0.0 S    00:00:00 sleep
root        3721       0  0.0  0.0 Ss   00:00:00 timeout
root        3727    3721  0.0  0.0 S    00:00:00 bash
root        3733    3727  0.0  0.0 S    00:00:00 bash
root        3752    3733  0.0  0.0 R    00:00:00 ps
$ wc -l linux_report/processes.txt
7 linux_report/processes.txt
```

The container only runs a few processes (`docker-init`, the `sleep` that keeps it alive, and the commands of this run), so the list is short. The processes in the list include the `ps`, `sort` and `head` of the script itself, because they were running at that moment.

### Default directory when Enter is pressed

The second answer is an empty line, so the script used the default `sysinfo_report`:

```bash
$ printf 'Vansh\n\n' | ./system_info.sh | grep -E 'Name entered|Report directory|Created'
Name entered      : Vansh
Report directory  : sysinfo_report
Created directory : sysinfo_report
Created file      : sysinfo_report/processes.txt (8 lines)
$ ls -d */
linux_report/
sysinfo_report/
```

### Why the prompts are not shown above

In both runs the `Enter your name:` prompts do not appear. That is how bash works: `read -p` only prints the prompt when the input comes from a terminal, and in my runs it came from a pipe/heredoc. To show the prompts once, I ran it through a pseudo-terminal (`script`), with a small `answers` function that types the two answers one second apart, and filtered the lines I wanted. The helper was:

```bash
answers() { sleep 1; printf 'Vansh Srivastava\n'; sleep 1; printf 'tty_report\n'; sleep 1; }
```

```bash
$ answers | script -qec ./system_info.sh /dev/null | grep -E "Enter|Name entered|Report directory|Created"
Enter your name: Vansh Srivastava
Enter a directory name for the report [sysinfo_report]: tty_report
Name entered      : Vansh Srivastava
Report directory  : tty_report
Created directory : tty_report
Created file      : tty_report/processes.txt (12 lines)
```

Now the prompts are there, followed by the answers echoed by the terminal, just like typing them by hand.

### Running it yourself

```bash
chmod +x system_info.sh
./system_info.sh            # type the answers when asked
cat sysinfo_report/processes.txt
```

## What I learned

- Command substitution `$(...)` stores a command's output in a variable; `${VAR:-default}` handles empty input.
- `read -p` needs bash, and its prompt only appears when stdin is a terminal; a pipe or heredoc can feed answers for automation.
- `>` overwrites a file (running the script again replaces `processes.txt`), `>>` would append.
- Small differences between GNU and BSD tools (`ps --sort`, `df` columns) matter if a script must run on both Linux and macOS; sticking to common options and piping to `sort` keeps one script for both.
- `bash -n` and ShellCheck catch mistakes before running a script.
