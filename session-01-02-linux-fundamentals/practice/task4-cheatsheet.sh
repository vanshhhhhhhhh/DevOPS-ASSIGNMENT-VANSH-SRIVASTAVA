#!/usr/bin/env bash
# Task 4: practise the commands from the course cheat sheets
# (session2-linux/basic-linux.pdf and ad-linux.pdf). Runs as root inside the
# Ubuntu 24.04 container (started with --init, so PID 1 is docker-init and
# the container's main process is "sleep infinity"). The process demos use
# unusual sleep durations so they never kill that main "sleep".
# Not runnable here: less/more and htop are interactive full-screen tools,
# !! and !n need an interactive shell, systemctl needs systemd (see Task 3).
source "$(dirname "$0")/lib.sh"

block t4-files
run 'ls -l /etc | head -5'
run 'cd /var/log && pwd'
run 'mkdir /tmp/devops_logs && cd /tmp/devops_logs && pwd'
run 'touch index.html'
run 'cp index.html index-copy.html'
run 'mv index-copy.html backup_index.html'
run 'ls -l'
run 'cd / && rm -rf /tmp/devops_logs && ls -d /tmp/devops_logs'

block t4-view
run 'cat /etc/os-release'
run 'head -n 3 /etc/passwd'
run 'tail -n 3 /etc/passwd'
run 'grep -n "^root" /etc/passwd'
run 'grep -c "nologin" /etc/passwd'
run 'tail -n 3 /var/log/dpkg.log'
run 'grep -c " install " /var/log/dpkg.log'
run 'grep -ic "error" /var/log/dpkg.log'
run 'grep -i "error" /var/log/dpkg.log | head -2'
run 'grep -iw "error" /var/log/dpkg.log || echo "no line contains the whole word error"'

block t4-proc
run 'ps'
run 'ps aux | head -5'
run 'top -b -n 1 | head -10'
run 'sleep 301 & echo "started PID $!"'
run 'nice -n 10 sleep 302 & echo "started PID $!"'
run 'nohup sleep 303 > /tmp/nohup.out 2>&1 & echo "started PID $!"'
run 'pgrep -a sleep'
run 'ps -o pid,ni,cmd -p "$(pgrep -f "sleep 302")"'
run 'renice -n 15 -p "$(pgrep -f "sleep 302")"'
run 'kill -9 "$(pgrep -f "sleep 301")"'
run 'pkill -f "sleep 30[23]"'
run 'sleep 0.5; pgrep -a sleep'

block t4-perms
run 'cd /tmp && echo "echo hello from script" > script.sh && ls -l script.sh'
run './script.sh'
run 'chmod 755 script.sh && ls -l script.sh'
run './script.sh'
run 'chmod u=rw,go= script.sh && stat -c "%a %A %n" script.sh'
run 'chown ubuntu:ubuntu script.sh && ls -l script.sh'
run 'umask'
run 'rm /tmp/script.sh'

block t4-packages
run 'apt-get update 2>&1 | tail -2'
run 'apt-get install -y htop 2>&1 | grep -E "^(The following NEW|  htop|Setting up)"'
run 'htop --version'
run 'command -v yum || echo "yum: not available on Ubuntu (RHEL/CentOS use yum or dnf)"'

block t4-disk
run 'df -h'
run 'du -sh /var/log'
run 'du -sh /usr/* 2>/dev/null | sort -h | tail -4'
run 'free -h'
run 'lsblk'
run 'findmnt --target / -o TARGET,SOURCE,FSTYPE'

block t4-sched
run 'echo "0 2 * * * /home/user/backup.sh" | crontab -'
run 'crontab -l'
run 'crontab -r && crontab -l'

block t4-users
run 'whoami'
run 'id'
run 'groups'
run 'who; echo "who exit code: $?"'
run 'w'
run 'last | head -3'

block t4-sysinfo
run 'uname -a'
run 'hostname'
run 'uptime'
run 'date'
run 'printf "set -o history\necho one > /dev/null\necho two > /dev/null\nhistory\n" | bash'

block t4-advanced
run 'vmstat 1 3'
run 'ss -tulwn'
run 'nc -l 80 > /dev/null & sleep 1; echo "nc listening, PID $!"'
run 'ss -tulwn'
run 'ss -plnt'
run 'netstat -tulnp'
run 'lsof -i :80'
run 'pkill -x nc; sleep 0.5; ss -tln'
run 'find / -type f -name "os-release" 2>/dev/null'
run 'file /bin/ls /etc/passwd'
run 'mkdir -p /tmp/xdemo && touch /tmp/xdemo/a.log /tmp/xdemo/b.log /tmp/xdemo/keep.txt'
run 'find /tmp/xdemo -name "*.log" | xargs rm -v'
run 'ls /tmp/xdemo && rm -r /tmp/xdemo'
run 'shopt -s expand_aliases; alias ll="ls -alF"; alias ll'
run 'll -d /tmp'
run 'ls -ltr /var/log | tail -3'
run 'dmesg | tail -2'
run 'echo "first line" > /tmp/app.log; ( sleep 1; echo "line written while tail -f was watching" >> /tmp/app.log ) & timeout 3 tail -f /tmp/app.log; echo "timeout stopped tail -f (exit code $?)"'
run 'rm /tmp/app.log /tmp/nohup.out'
