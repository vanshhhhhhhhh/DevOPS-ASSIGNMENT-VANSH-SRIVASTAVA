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
