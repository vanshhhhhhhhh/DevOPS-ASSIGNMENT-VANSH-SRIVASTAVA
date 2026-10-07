#!/usr/bin/env bash
# Task 1: git commit -a -m vs git commit -m
# Usage: task1-commit-a.sh <empty-work-dir>   (never run it inside a real repo)
source "$(dirname "$0")/lib.sh"
cd "$1" || exit 1

block g1-setup
run 'git init -q -b main commit-a-demo && cd commit-a-demo'
run 'echo "line 1" > app.txt && echo "# Notes" > notes.md'
run 'git add app.txt notes.md'
run 'git commit -m "Initial commit: add app.txt and notes.md"'

block g1-changes
run 'echo "line 2" >> app.txt'
run 'echo "I am a brand new file" > new.txt'
run 'git status --short'

block g1-commit-m
run 'git commit -m "Try plain commit -m without git add"'
run 'git status --short'

block g1-commit-a
run 'git commit -a -m "Commit with -a: stages modified tracked files"'
run 'git show --stat --format="%h %s" HEAD'
run 'git status --short'

block g1-add-new
run 'git add new.txt'
run 'git commit -m "Add new.txt with git add + commit -m"'
run 'git status --short'

block g1-selective
run 'echo "line 3" >> app.txt && echo "second line" >> new.txt'
run 'git add new.txt'
run 'git status --short'
run 'git commit -m "commit -m commits only what is staged (new.txt)"'
run 'git status --short'
run 'git commit -a -m "commit -a picks up the remaining app.txt change"'
run 'git status --short'

block g1-delete
run 'rm notes.md'
run 'git status --short'
run 'git commit -a -m "commit -a also stages deleted tracked files"'

block g1-log
run 'git log --oneline'
run 'git log --format="%h %s" --name-status'
