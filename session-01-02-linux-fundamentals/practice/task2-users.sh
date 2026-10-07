#!/usr/bin/env bash
# Task 2: adduser vs useradd (run as root inside the Ubuntu 24.04 container)
source "$(dirname "$0")/lib.sh"

# docker exec gives no terminal, so I feed the answers to adduser's prompts
# one by one through a pseudo-terminal (script). On a normal terminal you
# just type these answers. demo-password-123 is a throwaway demo password.
answers() {
  sleep 3; printf 'demo-password-123\n'; sleep 1; printf 'demo-password-123\n'
  sleep 1; printf 'Vansh Test User\n'
  for i in 1 2 3 4; do sleep 0.5; printf '\n'; done
  sleep 0.5; printf 'Y\n'; sleep 2
}

block t2-what
run 'dpkg -S /usr/sbin/useradd /usr/sbin/adduser'
run 'file /usr/sbin/useradd /usr/sbin/adduser'
run 'useradd -D'
run 'grep -E "^#(DSHELL|DHOME|SKEL|FIRST_UID|LAST_UID|USERGROUPS|ADD_EXTRA_GROUPS|EXTRA_GROUPS)=" /etc/adduser.conf'

block t2-useradd-plain
run 'useradd testuser1'
run 'getent passwd testuser1'
run 'ls -ld /home/testuser1'
run 'passwd -S testuser1'

block t2-useradd-flags
run 'useradd -m -s /bin/bash -c "Test User Two" testuser2'
run 'getent passwd testuser2'
run 'ls -la /home/testuser2'

block t2-adduser
run 'answers | script -qec "adduser vanshtest" /dev/null'

block t2-adduser-verify
run 'getent passwd vanshtest'
run 'id vanshtest'
run 'passwd -S vanshtest'
run 'ls -la /home/vanshtest'
run 'usermod -aG sudo vanshtest'
run 'groups vanshtest'
run 'su - vanshtest -c "whoami; pwd; echo \$SHELL"'

block t2-adduser-noninteractive
run 'adduser --disabled-password --comment "Script User" scriptuser'
run 'passwd -S scriptuser'

block t2-cleanup
run 'userdel testuser1'
run 'userdel -r testuser2'
run 'deluser --remove-home scriptuser'
run 'deluser --remove-home vanshtest'
run 'getent passwd testuser1 testuser2 scriptuser vanshtest || echo "no test users left"'
run 'ls /home'
