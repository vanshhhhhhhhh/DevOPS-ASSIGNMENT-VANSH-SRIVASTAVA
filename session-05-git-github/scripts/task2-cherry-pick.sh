#!/usr/bin/env bash
# Task 2: cherry-pick one commit from a feature branch into main
# Usage: task2-cherry-pick.sh <empty-work-dir>   (never run it inside a real repo)
source "$(dirname "$0")/lib.sh"
cd "$1" || exit 1

block g2-main
run 'git init -q -b main cherry-pick-demo && cd cherry-pick-demo'
run 'printf "# Cherry pick demo\nA tiny app for practising git.\n" > README.md && git add README.md && git commit -q -m "main: add README" && git log -1 --format="%h %s"'
run 'printf "def greet(name):\n    return \"Hello \" + name\n" > app.py && git add app.py && git commit -q -m "main: add greet function" && git log -1 --format="%h %s"'
run 'printf "PORT=8080\nDEBUG=false\n" > config.env && git add config.env && git commit -q -m "main: add config" && git log -1 --format="%h %s"'
run 'git log --oneline'

block g2-feature
run 'git switch -c feature'
run 'printf "\ndef login(user):\n    return user + \" logged in\"\n" >> app.py && git commit -q -a -m "feature: add login function" && git log -1 --format="%h %s"'
run 'printf "# Cherry pick demo\nA tiny app for practicing git.\n" > README.md && git diff --stat && git commit -q -a -m "fix: correct spelling in README" && git log -1 --format="%h %s"'
run 'printf "\ndef logout(user):\n    return user + \" logged out\"\n" >> app.py && git commit -q -a -m "feature: add logout function" && git log -1 --format="%h %s"'
run 'git log --oneline'

block g2-identify
run 'git log --oneline --graph --all'
run 'git log --oneline main..feature'
run 'git log --oneline --grep="fix:" feature'
run 'FIX=$(git log --format=%h --grep="fix:" feature); echo "commit to cherry-pick: $FIX"'
run 'git show --format="%h %s" "$FIX"'

block g2-pick
run 'git switch main'
run 'cat README.md'
run 'git cherry-pick "$FIX"'

block g2-verify
run 'git log --oneline'
run 'git log --oneline --graph --all'
run 'cat README.md'
run 'ls'
run 'grep -c "def " app.py'
run 'git cherry -v main feature'
run 'git branch --contains "$FIX"'
run 'git status'
