#!/usr/bin/env bash
# Networking commands run as root inside the throwaway Ubuntu 24.04 container
# (s01-ubuntu). Output is pasted into networking-commands.md.
source "$(dirname "$0")/lib.sh"

block l-ip
run 'ip addr'
run 'ip -br addr'
run 'ip -s link show eth0'
run 'ifconfig eth0'
run 'hostname'
run 'hostname -I'

block l-route
run 'ip route'
run 'ip route get 8.8.8.8'
run 'route -n'
run 'netstat -rn'

block l-arp
run 'ip neigh'
run 'ping -c 1 -W 1 172.17.0.1 > /dev/null'
run 'ip neigh'
run 'arp -n'

block l-files
run 'cat /etc/hosts'
run 'cat /etc/resolv.conf'
run 'grep "^hosts" /etc/nsswitch.conf'
run 'getent hosts localhost s01-ubuntu example.com'

block l-ping
run 'ping -c 3 google.com'
run 'ping -c 3 -W 2 192.0.2.1'

block l-trace
run 'traceroute -n -q 1 -m 10 -w 1 google.com'
run 'tracepath -n -m 10 google.com'

block l-nslookup
run 'nslookup google.com'
run 'nslookup -type=mx google.com'

block l-dig
run 'dig google.com'
run 'dig +short google.com'
run 'dig +short NS google.com'
run 'dig @8.8.8.8 +short example.com'
run 'dig -x 8.8.8.8 +short'
run 'dig -x 8.8.8.8 @8.8.8.8 +short'

block l-host
run 'host google.com'
run 'host -t txt example.com'

block l-curl
run 'curl -sI https://example.com'
run 'curl -s -o /dev/null -w "status=%{http_code} ip=%{remote_ip} time=%{time_total}s\n" https://example.com'
run 'curl -sv -o /dev/null https://example.com 2>&1 | grep -E "^\* (Connected|SSL connection|Server certificate)|^\*  subject|^> (GET|Host)|^< HTTP"'

block l-wget
run 'wget -nv -O /tmp/example.html https://example.com'
run 'ls -l /tmp/example.html && grep -o "<title>.*</title>" /tmp/example.html'

block l-ports
run 'ss -tulwn'
run 'nc -lk 8080 > /tmp/nc-server.log & sleep 1'
run 'ss -tlnp'
run 'netstat -tulnp'
run 'echo "hello from the nc client" | nc -q 1 localhost 8080; sleep 0.5; cat /tmp/nc-server.log'
run 'nc -zv example.com 443'
run 'nc -zv -w 2 localhost 8081'
run 'pkill -x nc; rm -f /tmp/nc-server.log /tmp/example.html'

block l-telnet
# telnet turns each \n into \r\n itself, so the request uses plain \n.
run '(printf "HEAD / HTTP/1.1\nHost: example.com\nConnection: close\n\n"; sleep 2) | telnet example.com 80'

block l-tcpdump
run '(sleep 1; curl -s -o /dev/null http://example.com) & timeout 8 tcpdump -i eth0 -nn -p -c 11 "tcp port 80"; wait'

block l-ipcalc
run 'ipcalc 197.23.45.10/24'
run 'ipcalc 120.27.1.0/8'
run 'ipcalc 192.168.1.0/26'

# Subnetting repo example and IP-quest questions (Task 1 in README.md)
block l-subnet
run 'ipcalc -b 192.168.1.0/24 26'
block l-ipquest
run 'ipcalc -b 192.168.0.0/24 | grep -E "HostMin|HostMax|Broadcast"'
run 'ipcalc -b 10.0.0.0/255.255.252.0 | grep -E "Netmask|Hosts/Net"'
run 'ipcalc -b 10.0.0.0/255.255.248.0 | grep -E "Netmask|Hosts/Net"'
run 'ipcalc -b 10.0.0.0/21 | grep -E "Netmask|Hosts/Net"'
# My Mac's Wi-Fi network (netmask 0xfffffe00 from ifconfig en0)
block l-ipcalc-mac
run 'ipcalc -b 10.10.12.130/23'
