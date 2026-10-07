#!/usr/bin/env bash
# Small helper used by the practice scripts in this folder.
# run "<command>"  prints the command with a "$ " prefix, then runs it in the
#                  current shell (so cd and variables persist) and shows
#                  stdout and stderr together, exactly like a terminal session.
# block <name>     prints a marker line; I used it to split the transcript
#                  into the sections shown in README.md.
run() {
  printf '$ %s\n' "$1"
  eval "$1" 2>&1
}
block() {
  printf '\n### BLOCK %s\n' "$1"
}
