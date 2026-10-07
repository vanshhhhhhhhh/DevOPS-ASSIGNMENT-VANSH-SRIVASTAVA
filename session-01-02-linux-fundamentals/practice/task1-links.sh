#!/usr/bin/env bash
# Task 1: soft links vs hard links (run inside the Ubuntu 24.04 container)
source "$(dirname "$0")/lib.sh"

block t1-setup
run 'rm -rf ~/links-demo && mkdir ~/links-demo && cd ~/links-demo'
run 'echo "Hello from the original file" > original.txt'
run 'ln original.txt hardlink.txt'
run 'ln -s original.txt softlink.txt'
run 'ls -li'

block t1-stat
run 'stat -c "%n | inode=%i | links=%h | type=%F | size=%s" original.txt hardlink.txt softlink.txt'
run 'readlink softlink.txt'
run 'readlink -f softlink.txt'

block t1-edit
run 'echo "Line added through the HARD link" >> hardlink.txt'
run 'echo "Line added through the SOFT link" >> softlink.txt'
run 'cat original.txt'

block t1-delete-original
run 'rm original.txt'
run 'ls -li'
run 'cat hardlink.txt'
run 'cat softlink.txt'
run 'find . -xtype l'

block t1-recreate
run 'echo "I am a brand new original.txt" > original.txt'
run 'ls -li'
run 'cat softlink.txt'
run 'cat hardlink.txt'

block t1-dirs
run 'mkdir mydir'
run 'ln mydir mydir-hard'
run 'ln -s mydir mydir-soft'
run 'ls -ld mydir mydir-soft'
run 'df -h /root /dev/shm | sed 1d'
run 'ln hardlink.txt /dev/shm/cross-fs-hard.txt'
run 'ln -s ~/links-demo/hardlink.txt /dev/shm/cross-fs-soft.txt'
run 'cat /dev/shm/cross-fs-soft.txt'

block t1-cleanup
run 'rm softlink.txt'
run 'unlink mydir-soft'
run 'rm /dev/shm/cross-fs-soft.txt'
run 'stat -c "%n links=%h" hardlink.txt'
run 'ln hardlink.txt second-hard.txt'
run 'stat -c "%n links=%h" hardlink.txt'
run 'rm second-hard.txt'
run 'stat -c "%n links=%h" hardlink.txt'
run 'ls -li'
run 'cd ~ && rm -rf ~/links-demo && ls -d ~/links-demo'
