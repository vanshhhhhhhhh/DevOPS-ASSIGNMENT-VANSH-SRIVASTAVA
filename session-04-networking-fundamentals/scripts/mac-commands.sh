#!/usr/bin/env bash
# Networking commands run on the Mac (macOS, BSD versions of the tools) and a
# few read-only ones inside the Colima VM. Output is pasted into
# networking-commands.md. VM commands are read-only (they only show state).
source "$(dirname "$0")/lib.sh"

block m-ip
run 'ifconfig en0 | grep -E "flags|inet "'
run 'ipconfig getifaddr en0'
run 'hostname'

block m-route
run 'netstat -rn -f inet | head -6'
run 'route -n get default'
run 'arp -n "$(route -n get default | awk "/gateway/ {print \$2}")"'

block m-ping
run 'ping -c 3 google.com'
run 'ping -c 3 -t 5 192.0.2.1'

block m-trace
run 'traceroute -n -q 1 -m 10 -w 2 google.com'

block m-dns
run 'nslookup google.com'
run 'scutil --dns | grep "nameserver\[0\]" | sort -u'

block m-ports
run 'netstat -an -p tcp | grep LISTEN | head -5'

block m-vm
run 'colima ssh -- ip -br addr | grep -v veth'
run 'colima ssh -- systemctl status systemd-networkd --no-pager -n 0'
run 'colima ssh -- grep nameserver /etc/resolv.conf'
run 'colima ssh -- sh -c "ss -lnt | grep -F 192.168.5.1:53"'

# DHCP: the last DHCP ACK the Mac received for Wi-Fi (only the useful fields;
# the full packet also contains the Mac's hardware address).
block m-dhcp
run 'ipconfig getpacket en0 | grep -E "^(op|yiaddr|dhcp_message_type|subnet_mask|router|domain_name_server|lease_time|server_identifier)"'
