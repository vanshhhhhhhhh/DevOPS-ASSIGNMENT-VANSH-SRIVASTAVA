#!/usr/bin/env bash
# Task 3: journalctl (run from the Mac; every command runs inside the Colima
# VM, which is Ubuntu 24.04 with systemd). Read-only: it only views logs.
source "$(dirname "$0")/lib.sh"

block t3-host
run 'colima ssh -- grep PRETTY_NAME /etc/os-release'
run 'colima ssh -- ps -p 1 -o comm='
run 'colima ssh -- systemctl --version | head -1'
run 'colima ssh -- id -nG'

block t3-system
run 'colima ssh -- journalctl --disk-usage'
run 'colima ssh -- journalctl --list-boots --no-pager'
run 'colima ssh -- journalctl -n 8 --no-pager'
run 'colima ssh -- journalctl -k -n 5 --no-pager'
run 'colima ssh -- journalctl -b -p err -n 5 --no-pager'

block t3-status
run 'colima ssh -- systemctl status docker --no-pager -n 0'

block t3-docker
run 'colima ssh -- journalctl -u docker.service -n 8 --no-pager'
run 'colima ssh -- sh -c "journalctl -u docker.service -b --no-pager | head -4"'
run 'colima ssh -- journalctl -u docker.service --since "15 min ago" --no-pager | wc -l'
run 'colima ssh -- journalctl -u docker.service -p warning --since "15 min ago" --no-pager'
run 'colima ssh -- sh -c "journalctl -u docker.service --since \"15 min ago\" --no-pager | grep -c level=error"'

block t3-other
run 'colima ssh -- journalctl -u containerd -n 5 --no-pager -o short-iso'
run 'colima ssh -- journalctl -u ssh -n 5 --no-pager'
run 'colima ssh -- journalctl -u ssh --since today --grep "Accepted" --no-pager | tail -3'
run 'colima ssh -- journalctl -u docker -u containerd -r -n 4 --no-pager'

block t3-json
run 'colima ssh -- journalctl -u ssh -n 1 -o json-pretty --no-pager'
run 'colima ssh -- journalctl -u ssh -n 3 -o cat --no-pager'

block t3-follow
# While journalctl -f is following the docker unit, start and remove a tiny
# container in the background so new log lines appear live.
( sleep 3; docker run --rm --name s01-journal-demo public.ecr.aws/docker/library/ubuntu:24.04 true >/dev/null 2>&1 ) &
run 'colima ssh -- timeout 10 journalctl -u docker -f -n 0 --no-pager'
wait
