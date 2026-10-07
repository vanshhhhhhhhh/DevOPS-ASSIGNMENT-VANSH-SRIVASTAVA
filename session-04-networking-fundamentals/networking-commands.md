# Networking Commands: Output and What I Understood

**Name:** Vansh Srivastava | **Enrollment No.:** 24bcs10567 | **Session:** 04, Task 2

I ran each command below and pasted the real output. After each one I wrote a short explanation of what the command does and what the output told me. Long outputs are trimmed with a `...` line.

**Where the commands ran** (more detail in [README.md](README.md#environment)):

- **Ubuntu container**: a throwaway Ubuntu 24.04 Docker container (`s01-ubuntu`) on my Mac, running as root. The Linux commands (`ip`, `ss`, `hostname -I`, `tracepath`, ...) ran here. Script: [`scripts/linux-commands.sh`](scripts/linux-commands.sh).
- **Mac**: macOS 26 on my laptop, connected to Wi-Fi. I used it where the container gives a misleading answer (`ping`, `traceroute`) and to compare the macOS versions of the tools. Script: [`scripts/mac-commands.sh`](scripts/mac-commands.sh).
- **Colima VM**: the Ubuntu VM that runs Docker on the Mac. Only read-only commands (`ip -br addr`, `systemctl status`).

The path from the container to the internet is: container `eth0` 172.17.0.2 -> `docker0` 172.17.0.1 in the Colima VM -> VM `eth0` 192.168.5.1 -> the Mac (`en0` 10.10.12.130) -> Wi-Fi router 10.10.12.1 -> ISP -> internet.

## Contents

1. [hostname and hostname -I](#1-hostname-and-hostname--i)
2. [ip addr and ip link](#2-ip-addr-and-ip-link)
3. [ifconfig](#3-ifconfig)
4. [ip route, route and netstat -rn](#4-ip-route-route-and-netstat--rn)
5. [arp and ip neigh](#5-arp-and-ip-neigh)
6. [/etc/hosts](#6-etchosts)
7. [/etc/resolv.conf](#7-etcresolvconf)
8. [ping](#8-ping)
9. [traceroute and tracepath](#9-traceroute-and-tracepath)
10. [nslookup](#10-nslookup)
11. [dig](#11-dig)
12. [host](#12-host)
13. [curl](#13-curl)
14. [wget](#14-wget)
15. [ss and netstat](#15-ss-and-netstat)
16. [nc (netcat)](#16-nc-netcat)
17. [telnet](#17-telnet)
18. [tcpdump](#18-tcpdump)
19. [systemctl for the network service](#19-systemctl-for-the-network-service)

## 1. hostname and hostname -I

Ran in: Ubuntu container

```bash
$ hostname
s01-ubuntu
$ hostname -I
172.17.0.2 
```

Ran in: Mac

```bash
$ hostname
whenoms-MacBook-Air.local
```

**What I understood:** `hostname` prints the machine's name. Docker set the container's name to `s01-ubuntu` because I started it with `--hostname`. `hostname -I` (capital i, Linux only) prints all IP addresses of the machine on one line without the loopback address, which is the quickest way to get "my IP" in a script. macOS `hostname` has no `-I`; there I use `ipconfig getifaddr en0` (section 3).

## 2. ip addr and ip link

Ran in: Ubuntu container

```bash
$ ip addr
1: lo: <LOOPBACK,UP,LOWER_UP> mtu 65536 qdisc noqueue state UNKNOWN group default qlen 1000
    link/loopback 00:00:00:00:00:00 brd 00:00:00:00:00:00
    inet 127.0.0.1/8 scope host lo
       valid_lft forever preferred_lft forever
    inet6 ::1/128 scope host 
       valid_lft forever preferred_lft forever
2: eth0@if111: <BROADCAST,MULTICAST,UP,LOWER_UP> mtu 1500 qdisc noqueue state UP group default 
    link/ether 26:f4:58:2c:d5:cd brd ff:ff:ff:ff:ff:ff link-netnsid 0
    inet 172.17.0.2/16 brd 172.17.255.255 scope global eth0
       valid_lft forever preferred_lft forever
$ ip -br addr
lo               UNKNOWN        127.0.0.1/8 ::1/128 
eth0@if111       UP             172.17.0.2/16 
$ ip -s link show eth0
2: eth0@if111: <BROADCAST,MULTICAST,UP,LOWER_UP> mtu 1500 qdisc noqueue state UP mode DEFAULT group default 
    link/ether 26:f4:58:2c:d5:cd brd ff:ff:ff:ff:ff:ff link-netnsid 0
    RX:  bytes packets errors dropped  missed   mcast           
      80953948   10885      0       0       0       0 
    TX:  bytes packets errors dropped carrier collsns           
        459563    5335      0       0       0       0 
```

**What I understood:** `ip` (from the `iproute2` package) is the modern Linux tool for interfaces, addresses, routes and neighbours.

- `ip addr` (or `ip a`) lists every interface with its addresses. `lo` is loopback (127.0.0.1/8). `eth0` has `172.17.0.2/16`, so the container is on Docker's default bridge network 172.17.0.0/16; `link/ether` is its MAC address, `mtu 1500` the largest packet size, `state UP` means the link is up. `eth0@if111` means the other end of this virtual cable is interface 111 in the VM (a `veth` pair).
- `ip -br addr` is the brief, one-line-per-interface view.
- `ip -s link` adds counters: about 81 MB received and 460 KB sent, with no errors or drops. Most of the received bytes are the apt packages I installed.

## 3. ifconfig

Ran in: Ubuntu container

```bash
$ ifconfig eth0
eth0: flags=4163<UP,BROADCAST,RUNNING,MULTICAST>  mtu 1500
        inet 172.17.0.2  netmask 255.255.0.0  broadcast 172.17.255.255
        ether 26:f4:58:2c:d5:cd  txqueuelen 0  (Ethernet)
        RX packets 10885  bytes 80953948 (80.9 MB)
        RX errors 0  dropped 0  overruns 0  frame 0
        TX packets 5335  bytes 459563 (459.5 KB)
        TX errors 0  dropped 0 overruns 0  carrier 0  collisions 0
```

Ran in: Mac

```bash
$ ifconfig en0 | grep -E "flags|inet "
en0: flags=8863<UP,BROADCAST,SMART,RUNNING,SIMPLEX,MULTICAST> mtu 1500
	inet 10.10.12.130 netmask 0xfffffe00 broadcast 10.10.13.255
$ ipconfig getifaddr en0
10.10.12.130
```

**What I understood:** `ifconfig` is the older tool (from `net-tools`, not installed by default on new Ubuntu) and shows the same information as `ip addr` + `ip -s link`. On Linux the netmask is printed as `255.255.0.0`. On macOS `ifconfig` is still the standard tool and shows the netmask in hex: `0xfffffe00` = 255.255.254.0 = `/23`, so my Wi-Fi network 10.10.12.0/23 has 510 usable addresses (checked with `ipcalc` in the README). `ipconfig getifaddr en0` is the macOS shortcut to print just the IP of `en0` (Wi-Fi).

## 4. ip route, route and netstat -rn

Ran in: Ubuntu container

```bash
$ ip route
default via 172.17.0.1 dev eth0 
172.17.0.0/16 dev eth0 proto kernel scope link src 172.17.0.2 
$ ip route get 8.8.8.8
8.8.8.8 via 172.17.0.1 dev eth0 src 172.17.0.2 uid 0 
    cache 
$ route -n
Kernel IP routing table
Destination     Gateway         Genmask         Flags Metric Ref    Use Iface
0.0.0.0         172.17.0.1      0.0.0.0         UG    0      0        0 eth0
172.17.0.0      0.0.0.0         255.255.0.0     U     0      0        0 eth0
$ netstat -rn
Kernel IP routing table
Destination     Gateway         Genmask         Flags   MSS Window  irtt Iface
0.0.0.0         172.17.0.1      0.0.0.0         UG        0 0          0 eth0
172.17.0.0      0.0.0.0         255.255.0.0     U         0 0          0 eth0
```

Ran in: Mac

```bash
$ netstat -rn -f inet | head -6
Routing tables

Internet:
Destination        Gateway            Flags               Netif Expire
default            10.10.12.1         UGScg                 en0       
10.10.12/23        link#11            UCS                   en0      !
$ route -n get default
   route to: default
destination: default
       mask: default
    gateway: 10.10.12.1
  interface: en0
      flags: <UP,GATEWAY,DONE,STATIC,PRCLONING,GLOBAL>
 recvpipe  sendpipe  ssthresh  rtt,msec    rttvar  hopcount      mtu     expire
       0         0         0         0         0         0      1500         0 
```

**What I understood:** The routing table decides where each packet goes.

- In the container there are only two routes: 172.17.0.0/16 is directly connected on `eth0` (`scope link`), and everything else (`default`, shown as `0.0.0.0` with flag `G` = gateway) goes to 172.17.0.1, the Docker bridge in the VM.
- `ip route get 8.8.8.8` asks the kernel which route a specific address would use: via 172.17.0.1 on `eth0` with source address 172.17.0.2.
- `route -n` and `netstat -rn` are the older `net-tools` versions of the same table (`-n` = do not resolve names).
- On the Mac, the default gateway is my Wi-Fi router 10.10.12.1 on `en0`, and `route -n get default` shows the details of that route.

## 5. arp and ip neigh

Ran in: Ubuntu container

```bash
$ ip neigh
172.17.0.1 dev eth0 lladdr 2e:5e:3d:0f:82:47 REACHABLE 
$ ping -c 1 -W 1 172.17.0.1 > /dev/null
$ ip neigh
172.17.0.1 dev eth0 lladdr 2e:5e:3d:0f:82:47 REACHABLE 
$ arp -n
Address                  HWtype  HWaddress           Flags Mask            Iface
172.17.0.1               ether   2e:5e:3d:0f:82:47   C                     eth0
```

Ran in: Mac (ARP entry of my default gateway)

```bash
$ arp -n "$(route -n get default | awk "/gateway/ {print \$2}")"
? (10.10.12.1) at d0:ea:11:32:0:19 on en0 ifscope [ethernet]
```

**What I understood:** ARP maps an IP address to a MAC address on the local network; a packet can only be delivered on Ethernet/Wi-Fi once the MAC of the next hop is known. `ip neigh` (or the older `arp -n`) shows this cache. The container only ever talks to its gateway 172.17.0.1, so that is the only entry. Its state is `REACHABLE` (confirmed recently; I pinged the gateway in between to be sure there was traffic). Other states are `STALE` (not confirmed for a while, will be checked on next use), `DELAY`/`PROBE` (being checked) and `FAILED`. On the Mac, `arp` shows the MAC of the Wi-Fi router.

## 6. /etc/hosts

Ran in: Ubuntu container

```bash
$ cat /etc/hosts
127.0.0.1	localhost
::1	localhost ip6-localhost ip6-loopback
fe00::	ip6-localnet
ff00::	ip6-mcastprefix
ff02::1	ip6-allnodes
ff02::2	ip6-allrouters
172.17.0.2	s01-ubuntu
```

**What I understood:** `/etc/hosts` is a static list of name -> IP mappings that is checked before DNS. It has `localhost` for 127.0.0.1 and ::1, and Docker added a line so the container can resolve its own name `s01-ubuntu` to 172.17.0.2. Adding a line here is a quick way to point a name at a test server without changing DNS.

## 7. /etc/resolv.conf

Ran in: Ubuntu container

```bash
$ cat /etc/resolv.conf
# Generated by Docker Engine.
# This file can be edited; Docker Engine will not make further changes once it
# has been modified.

nameserver 192.168.5.1

# Based on host file: '/etc/resolv.conf' (legacy)
# Overrides: []
$ grep "^hosts" /etc/nsswitch.conf
hosts:          files dns
$ getent hosts localhost s01-ubuntu example.com
::1             localhost ip6-localhost ip6-loopback
172.17.0.2      s01-ubuntu
172.66.147.243  example.com
104.20.23.154   example.com
```

Ran in: Colima VM

```bash
$ colima ssh -- grep nameserver /etc/resolv.conf
nameserver 192.168.5.1
$ colima ssh -- sh -c "ss -lnt | grep -F 192.168.5.1:53"
LISTEN 0      32                          192.168.5.1:53         0.0.0.0:*          
```

**What I understood:** `/etc/resolv.conf` tells the resolver which DNS server to ask. Docker generated it with `nameserver 192.168.5.1`, which is the Colima VM's own address; inside the VM a DNS server listens on 192.168.5.1:53 and answers for the containers. `/etc/nsswitch.conf` sets the order: `files` (`/etc/hosts`) first, then `dns`. `getent hosts` uses exactly that order, so it found `localhost` and `s01-ubuntu` in `/etc/hosts` and `example.com` through DNS.

## 8. ping

Ran in: Mac

```bash
$ ping -c 3 google.com
PING google.com (142.250.143.138): 56 data bytes
64 bytes from 142.250.143.138: icmp_seq=0 ttl=114 time=91.202 ms
64 bytes from 142.250.143.138: icmp_seq=1 ttl=114 time=103.274 ms
64 bytes from 142.250.143.138: icmp_seq=2 ttl=114 time=17.361 ms

--- google.com ping statistics ---
3 packets transmitted, 3 packets received, 0.0% packet loss
round-trip min/avg/max/stddev = 17.361/70.612/103.274/37.976 ms
$ ping -c 3 -t 5 192.0.2.1
PING 192.0.2.1 (192.0.2.1): 56 data bytes
Request timeout for icmp_seq 0
Request timeout for icmp_seq 1

--- 192.0.2.1 ping statistics ---
3 packets transmitted, 0 packets received, 100.0% packet loss
```

Ran in: Ubuntu container

```bash
$ ping -c 3 google.com
PING google.com (142.250.143.139) 56(84) bytes of data.
64 bytes from 142.250.143.139: icmp_seq=1 ttl=63 time=0.089 ms
64 bytes from 142.250.143.139: icmp_seq=2 ttl=63 time=0.175 ms
64 bytes from 142.250.143.139: icmp_seq=3 ttl=63 time=0.145 ms

--- google.com ping statistics ---
3 packets transmitted, 3 received, 0% packet loss, time 2048ms
rtt min/avg/max/mdev = 0.089/0.136/0.175/0.035 ms
$ ping -c 3 -W 2 192.0.2.1
PING 192.0.2.1 (192.0.2.1) 56(84) bytes of data.
64 bytes from 192.0.2.1: icmp_seq=1 ttl=63 time=0.128 ms
64 bytes from 192.0.2.1: icmp_seq=2 ttl=63 time=0.190 ms
64 bytes from 192.0.2.1: icmp_seq=3 ttl=63 time=0.160 ms

--- 192.0.2.1 ping statistics ---
3 packets transmitted, 3 received, 0% packet loss, time 2031ms
rtt min/avg/max/mdev = 0.128/0.159/0.190/0.025 ms
```

**What I understood:** `ping` sends ICMP echo requests and measures the round-trip time. `-c 3` stops after 3 packets (on Linux it would run forever otherwise). From the Mac, google.com answered in 17 to 103 ms with TTL 114, and `192.0.2.1` (an address reserved for documentation, which nobody uses) did not answer at all, as expected.

From the container the result looks perfect but is **not real**: 0.1 ms to Google is physically impossible (the Mac needs at least 17 ms), and even 192.0.2.1, which does not exist, "replies". The TTL is 63 (64 minus one hop) for both. So the replies must be generated locally by the virtual network layer between the Colima VM and the Mac, not by Google. Lesson: inside this kind of container, `ping` only proves that the local network stack works; to test real reachability I should use the Mac or a TCP test (`curl`, `nc -z`), which the tcpdump in section 18 shows going to the real server.

## 9. traceroute and tracepath

Ran in: Mac

```bash
$ traceroute -n -q 1 -m 10 -w 2 google.com
traceroute: Warning: google.com has multiple addresses; using 142.250.143.138
traceroute to google.com (142.250.143.138), 10 hops max, 40 byte packets
 1  10.10.12.1  6.572 ms
 2  202.131.146.145  31.895 ms
 3  172.20.20.17  26.525 ms
 4  72.14.208.165  16.399 ms
 5  142.250.143.138  20.550 ms
```

Ran in: Ubuntu container

```bash
$ traceroute -n -q 1 -m 10 -w 1 google.com
traceroute to google.com (142.250.143.139), 10 hops max, 60 byte packets
 1  172.17.0.1  0.012 ms
 2  *
 3  *
 4  *
 5  *
 6  *
 7  *
 8  *
 9  *
10  *
$ tracepath -n -m 10 google.com
 1?: [LOCALHOST]                      pmtu 1500
 1:  172.17.0.1                                            0.016ms 
 1:  172.17.0.1                                            0.005ms 
 2:  no reply
 3:  no reply
 4:  no reply
 5:  no reply
 6:  no reply
 7:  no reply
 8:  no reply
 9:  no reply
10:  no reply
     Too many hops: pmtu 1500
     Resume: pmtu 1500 
```

**What I understood:** `traceroute` sends packets with TTL 1, 2, 3, ... Every router that drops a packet because its TTL reached 0 sends back an ICMP "time exceeded", and that reveals the router's address. `-n` skips reverse DNS, `-q 1` sends one probe per hop and `-m 10` stops after 10 hops.

- From the Mac the path to Google is 5 hops: my Wi-Fi router (10.10.12.1), two ISP routers (202.131.146.145 and the private 172.20.20.17 inside the ISP), a Google edge router (72.14.208.165) and the Google server.
- From the container only hop 1 (172.17.0.1, the Docker bridge in the VM) answers; after that every hop is `*` / `no reply`. The Mac sees all the hops, so apparently the virtual network between the VM and the Mac does not pass the "time exceeded" messages back (the same layer that fakes the `ping` replies).
- `tracepath` does the same with UDP and also reports the path MTU (`pmtu 1500`); it does not need root.

## 10. nslookup

Ran in: Ubuntu container

```bash
$ nslookup google.com
Server:		192.168.5.1
Address:	192.168.5.1#53

Non-authoritative answer:
Name:	google.com
Address: 142.250.143.139
Name:	google.com
Address: 142.250.143.113
Name:	google.com
Address: 142.250.143.101
Name:	google.com
Address: 142.250.143.102
Name:	google.com
Address: 142.250.143.138
Name:	google.com
Address: 142.250.143.100

$ nslookup -type=mx google.com
Server:		192.168.5.1
Address:	192.168.5.1#53

Non-authoritative answer:
google.com	mail exchanger = 10 smtp.google.com.

Authoritative answers can be found from:
```

Ran in: Mac

```bash
$ nslookup google.com
Server:		8.8.8.8
Address:	8.8.8.8#53

Non-authoritative answer:
Name:	google.com
Address: 142.250.143.101
Name:	google.com
Address: 142.250.143.113
Name:	google.com
Address: 142.250.143.100
Name:	google.com
Address: 142.250.143.138
Name:	google.com
Address: 142.250.143.139
Name:	google.com
Address: 142.250.143.102

$ scutil --dns | grep "nameserver\[0\]" | sort -u
  nameserver[0] : 8.8.8.8
```

**What I understood:** `nslookup` asks a DNS server for a name. `Server:` is the DNS server used (192.168.5.1 in the container, 8.8.8.8 on the Mac; `scutil --dns` confirms that 8.8.8.8 is the Mac's configured DNS server). "Non-authoritative answer" means it came from a resolver/cache, not from Google's own name servers. google.com has six IPv4 addresses (load balancing). `-type=mx` asks for the mail server instead.

## 11. dig

Ran in: Ubuntu container

```bash
$ dig google.com

; <<>> DiG 9.18.39-0ubuntu0.24.04.7-Ubuntu <<>> google.com
;; global options: +cmd
;; Got answer:
;; ->>HEADER<<- opcode: QUERY, status: NOERROR, id: 38156
;; flags: qr rd ra; QUERY: 1, ANSWER: 6, AUTHORITY: 0, ADDITIONAL: 0

;; QUESTION SECTION:
;google.com.			IN	A

;; ANSWER SECTION:
google.com.		0	IN	A	142.250.143.139
google.com.		0	IN	A	142.250.143.113
google.com.		0	IN	A	142.250.143.101
google.com.		0	IN	A	142.250.143.102
google.com.		0	IN	A	142.250.143.138
google.com.		0	IN	A	142.250.143.100

;; Query time: 2 msec
;; SERVER: 192.168.5.1#53(192.168.5.1) (UDP)
;; WHEN: Wed Oct 07 18:04:08 UTC 2026
;; MSG SIZE  rcvd: 184

$ dig +short google.com
142.250.143.139
142.250.143.113
142.250.143.101
142.250.143.102
142.250.143.138
142.250.143.100
$ dig +short NS google.com
ns1.google.com.
ns3.google.com.
ns4.google.com.
ns2.google.com.
$ dig @8.8.8.8 +short example.com
104.20.23.154
172.66.147.243
$ dig -x 8.8.8.8 +short
$ dig -x 8.8.8.8 @8.8.8.8 +short
dns.google.
```

**What I understood:** `dig` is the most detailed DNS tool.

- The full output shows the question, the answer section (name, TTL, class `IN`, type `A`, address), the server used and the query time (2 ms). The TTL is 0, so Colima's DNS forwarder tells clients not to cache the answer. `status: NOERROR` means the lookup worked.
- `+short` prints only the answers. `NS` asks which name servers are authoritative for google.com.
- `@8.8.8.8` sends the query to a specific server (Google Public DNS) instead of the one in `/etc/resolv.conf`.
- `-x` does a reverse lookup (IP -> name). Through Colima's DNS server it returned nothing, but asking 8.8.8.8 directly gave `dns.google.`, so the local DNS forwarder in the VM does not handle reverse lookups. Using `@server` is a quick way to find out whether a DNS problem is in my local resolver or not.

## 12. host

Ran in: Ubuntu container

```bash
$ host google.com
google.com has address 142.250.143.139
google.com has address 142.250.143.113
google.com has address 142.250.143.101
google.com has address 142.250.143.102
google.com has address 142.250.143.138
google.com has address 142.250.143.100
google.com mail is handled by 10 smtp.google.com.
$ host -t txt example.com
example.com descriptive text "v=spf1 -all"
example.com descriptive text "_k2n1y4vw3qtb4skdx9e7dxt97qrmmq9"
```

**What I understood:** `host` is the simplest DNS lookup tool: one readable line per record. By default it shows A, AAAA and MX records; `-t` picks a record type. The TXT records of example.com include an SPF record (`v=spf1 -all`) saying that no server is allowed to send mail for that domain.

## 13. curl

Ran in: Ubuntu container

```bash
$ curl -sI https://example.com
HTTP/2 200 
date: Wed, 07 Oct 2026 18:04:08 GMT
content-type: text/html; charset=utf-8
server: cloudflare
last-modified: Sun, 04 Oct 2026 20:44:03 GMT
allow: GET, HEAD
accept-ranges: bytes
age: 6718
cf-cache-status: HIT
cf-ray: a46ed39a891beccd-BOM
alt-svc: h3=":443"; ma=86400

$ curl -s -o /dev/null -w "status=%{http_code} ip=%{remote_ip} time=%{time_total}s\n" https://example.com
status=200 ip=172.66.147.243 time=0.112589s
$ curl -sv -o /dev/null https://example.com 2>&1 | grep -E "^\* (Connected|SSL connection|Server certificate)|^\*  subject|^> (GET|Host)|^< HTTP"
* Connected to example.com (172.66.147.243) port 443
* SSL connection using TLSv1.3 / TLS_AES_256_GCM_SHA384 / X25519 / id-ecPublicKey
* Server certificate:
*  subject: CN=example.com
*  subjectAltName: host "example.com" matched cert's "example.com"
> GET / HTTP/2
> Host: example.com
< HTTP/2 200 
```

**What I understood:** `curl` makes HTTP(S) requests from the command line.

- `-I` sends a HEAD request and shows only the response headers: `HTTP/2 200` (OK), served by Cloudflare from its cache (`cf-cache-status: HIT`, `cf-ray ... -BOM` = Mumbai edge).
- `-w` prints chosen details of the transfer; here the status code, the IP it connected to and the total time (0.11 s). This is how I would check a health endpoint in a script.
- `-v` shows the connection steps: TCP connect to port 443, the TLS 1.3 handshake and certificate check (`CN=example.com` matched), then the request (`> GET / HTTP/2`) and the response status (`< HTTP/2 200`). So `curl` tests DNS, TCP, TLS and HTTP in one go.

## 14. wget

Ran in: Ubuntu container

```bash
$ wget -nv -O /tmp/example.html https://example.com
2026-10-07 18:04:09 URL:https://example.com/ [577] -> "/tmp/example.html" [1]
$ ls -l /tmp/example.html && grep -o "<title>.*</title>" /tmp/example.html
-rw-r--r-- 1 root root 577 Oct  4 20:44 /tmp/example.html
<title>Example Domain</title>
```

**What I understood:** `wget` downloads files to disk (where `curl` writes to the terminal by default). `-O` sets the output file name and `-nv` prints one summary line instead of a progress bar. The page is 577 bytes and its title is "Example Domain". `wget` is useful in scripts for downloading packages or artefacts, and it can retry and resume downloads.

## 15. ss and netstat

Ran in: Ubuntu container

```bash
$ ss -tulwn
Netid State Recv-Q Send-Q Local Address:Port Peer Address:PortProcess
$ nc -lk 8080 > /tmp/nc-server.log & sleep 1
$ ss -tlnp
State  Recv-Q Send-Q Local Address:Port Peer Address:PortProcess
LISTEN 0      1            0.0.0.0:8080      0.0.0.0:*    users:(("nc",pid=4042,fd=3))
$ netstat -tulnp
Active Internet connections (only servers)
Proto Recv-Q Send-Q Local Address           Foreign Address         State       PID/Program name    
tcp        0      0 0.0.0.0:8080            0.0.0.0:*               LISTEN      4042/nc             
```

Ran in: Mac (first 5 listening TCP sockets)

```bash
$ netstat -an -p tcp | grep LISTEN | head -5
tcp6       0      0  ::1.18280              *.*                    LISTEN     
tcp4       0      0  127.0.0.1.18280        *.*                    LISTEN     
tcp4       0      0  127.0.0.1.8217         *.*                    LISTEN     
tcp4       0      0  *.8182                 *.*                    LISTEN     
tcp4       0      0  *.8181                 *.*                    LISTEN     
```

**What I understood:** `ss` (socket statistics, the modern tool) and `netstat` (older, `net-tools`) show open sockets. Options: `-t` TCP, `-u` UDP, `-l` listening only, `-n` numbers instead of names, `-p` the process (needs root to see other users' processes), `-w` raw sockets.

- At first nothing was listening in the container.
- After I started `nc -lk 8080` (a tiny TCP server), both tools show `0.0.0.0:8080` in state `LISTEN`, owned by `nc` with its PID. `0.0.0.0` means it accepts connections on every interface.
- This is the first thing to check when "the app is running but I cannot connect": is it listening, on which port, and on `127.0.0.1` only or on all interfaces?
- The macOS `netstat` uses `address.port` format; `127.0.0.1.18280` is only reachable from the Mac itself, `*.8181` from anywhere.

## 16. nc (netcat)

Ran in: Ubuntu container

```bash
$ echo "hello from the nc client" | nc -q 1 localhost 8080; sleep 0.5; cat /tmp/nc-server.log
hello from the nc client
$ nc -zv example.com 443
Connection to example.com (104.20.23.154) 443 port [tcp/https] succeeded!
$ nc -zv -w 2 localhost 8081
nc: connect to localhost (::1) port 8081 (tcp) failed: Connection refused
nc: connect to localhost (127.0.0.1) port 8081 (tcp) failed: Connection refused
$ pkill -x nc; rm -f /tmp/nc-server.log /tmp/example.html
```

**What I understood:** `nc` reads and writes raw TCP/UDP connections.

- With the `nc -lk 8080` server from section 15 running, `echo ... | nc localhost 8080` sent one line, and the server wrote it to its log file. That is a full TCP client/server exchange without any real application.
- `nc -zv host port` only checks whether a TCP port is open (`-z` = connect and close, no data; `-v` = verbose). Port 443 on example.com succeeded; port 8081 on localhost was refused, for both IPv6 (::1) and IPv4 (127.0.0.1), because nothing listens there.
- "Connection refused" (something answered "no") is different from a timeout (no answer at all, often a firewall).

## 17. telnet

Ran in: Ubuntu container

```bash
$ (printf "HEAD / HTTP/1.1\nHost: example.com\nConnection: close\n\n"; sleep 2) | telnet example.com 80
Trying 104.20.23.154...
Connected to example.com.
Escape character is '^]'.
HTTP/1.1 200 OK
Date: Wed, 07 Oct 2026 18:04:11 GMT
Content-Type: text/html; charset=utf-8
Connection: close
Server: cloudflare
Last-Modified: Sun, 04 Oct 2026 20:44:03 GMT
Allow: GET, HEAD
Accept-Ranges: bytes
Age: 6723
cf-cache-status: HIT
CF-RAY: a46ed3ae2b02d7f3-BOM
alt-svc: h3=":443"; ma=86400

Connection closed by foreign host.
```

**What I understood:** `telnet host port` opens a plain TCP connection, so it is a classic way to test whether a port is reachable and to talk to text protocols by hand. Here I typed (piped) an HTTP `HEAD` request and got `HTTP/1.1 200 OK` back. My first try used `\r\n` line endings and got `400 Bad Request`, because telnet already turns each newline into `\r\n`, so the server received `\r\r\n`. Telnet sends everything in clear text, so it must never be used for remote logins; `ssh` replaced it for that.

## 18. tcpdump

Ran in: Ubuntu container

```bash
$ (sleep 1; curl -s -o /dev/null http://example.com) & timeout 8 tcpdump -i eth0 -nn -p -c 11 "tcp port 80"; wait
tcpdump: verbose output suppressed, use -v[v]... for full protocol decode
listening on eth0, link-type EN10MB (Ethernet), snapshot length 262144 bytes
18:04:14.650498 IP 172.17.0.2.55188 > 172.66.147.243.80: Flags [S], seq 3890903917, win 64240, options [mss 1460,sackOK,TS val 547402849 ecr 0,nop,wscale 7], length 0
18:04:14.713367 IP 172.66.147.243.80 > 172.17.0.2.55188: Flags [S.], seq 131738336, ack 3890903918, win 29184, options [mss 1460,sackOK,TS val 752261405 ecr 547402849,nop,wscale 7], length 0
18:04:14.713420 IP 172.17.0.2.55188 > 172.66.147.243.80: Flags [.], ack 1, win 502, options [nop,nop,TS val 547402911 ecr 752261405], length 0
18:04:14.713525 IP 172.17.0.2.55188 > 172.66.147.243.80: Flags [P.], seq 1:75, ack 1, win 502, options [nop,nop,TS val 547402912 ecr 752261405], length 74: HTTP: GET / HTTP/1.1
18:04:14.713718 IP 172.66.147.243.80 > 172.17.0.2.55188: Flags [.], ack 75, win 227, options [nop,nop,TS val 752261406 ecr 547402912], length 0
18:04:14.735377 IP 172.66.147.243.80 > 172.17.0.2.55188: Flags [P.], seq 1:937, ack 75, win 4096, options [nop,nop,TS val 752261427 ecr 547402912], length 936: HTTP: HTTP/1.1 200 OK
18:04:14.735388 IP 172.17.0.2.55188 > 172.66.147.243.80: Flags [.], ack 937, win 495, options [nop,nop,TS val 547402933 ecr 752261427], length 0
18:04:14.735476 IP 172.17.0.2.55188 > 172.66.147.243.80: Flags [F.], seq 75, ack 937, win 495, options [nop,nop,TS val 547402934 ecr 752261427], length 0
18:04:14.735550 IP 172.66.147.243.80 > 172.17.0.2.55188: Flags [.], ack 76, win 4095, options [nop,nop,TS val 752261427 ecr 547402933], length 0
18:04:14.754889 IP 172.66.147.243.80 > 172.17.0.2.55188: Flags [F.], seq 937, ack 76, win 4096, options [nop,nop,TS val 752261446 ecr 547402934], length 0
18:04:14.754896 IP 172.17.0.2.55188 > 172.66.147.243.80: Flags [.], ack 938, win 495, options [nop,nop,TS val 547402953 ecr 752261446], length 0
11 packets captured
11 packets received by filter
0 packets dropped by kernel
```

**What I understood:** `tcpdump` captures packets on an interface. `-i eth0` picks the interface, `-nn` keeps numbers instead of names, `-p` does not switch the card into promiscuous mode, `-c 11` stops after 11 packets and `"tcp port 80"` is the capture filter. While it was running, `curl` fetched `http://example.com`, and the capture shows the whole TCP conversation from the session notes:

1. `[S]` SYN, `[S.]` SYN-ACK, `[.]` ACK: the three-way handshake.
2. `[P.]` with `GET / HTTP/1.1` (74 bytes) from my side, and an ACK from the server.
3. `[P.]` with `HTTP/1.1 200 OK` (936 bytes) from the server, and my ACK.
4. `[F.]` FIN from each side and the final ACKs: the connection is closed.

The SYN-ACK came back after 63 ms, which is a real network round trip. This confirms that TCP traffic from the container really reaches the internet, unlike the ICMP `ping` replies in section 8.

## 19. systemctl for the network service

Ran in: Colima VM (read-only)

```bash
$ colima ssh -- ip -br addr | grep -v veth
lo               UNKNOWN        127.0.0.1/8 ::1/128 
eth0             UP             192.168.5.1/24 metric 200 fe80::5055:55ff:feb8:9356/64 
docker0          UP             172.17.0.1/16 fe80::2c5e:3dff:fe0f:8247/64 
br-895d0961dada  UP             192.168.49.1/24 fe80::4849:67ff:fe82:7e19/64 
br-88fd726f7705  UP             172.22.0.1/16 fe80::d8d2:cdff:fe4c:e95/64 
br-1dbff289f883  UP             172.19.0.1/16 fe80::f4f3:22ff:fee0:b09e/64 
br-9e1f13521373  UP             172.20.0.1/16 fe80::281c:5dff:fea6:a1c0/64 
br-8a84c581b11e  UP             172.21.0.1/16 fe80::98d8:7eff:fe9f:6c45/64 
$ colima ssh -- systemctl status systemd-networkd --no-pager -n 0
● systemd-networkd.service - Network Configuration
     Loaded: loaded (/usr/lib/systemd/system/systemd-networkd.service; enabled; preset: enabled)
     Active: active (running) since Wed 2026-10-07 23:04:32 IST; 30min ago
TriggeredBy: ● systemd-networkd.socket
       Docs: man:systemd-networkd.service(8)
             man:org.freedesktop.network1(5)
   Main PID: 443 (systemd-network)
     Status: "Processing requests..."
      Tasks: 1 (limit: 11853)
   FD Store: 0 (limit: 512)
     Memory: 4.4M (peak: 5.1M)
        CPU: 510ms
     CGroup: /system.slice/systemd-networkd.service
             └─443 /usr/lib/systemd/systemd-networkd
```

**What I understood:** The Network-Troubleshooting repo suggests `systemctl status NetworkManager` to check that the network service is running. Ubuntu server images (like the Colima VM) use `systemd-networkd` instead, and it is `active (running)`. `ip -br addr` in the VM (I filtered out the many `veth` interfaces of running containers) shows its own `eth0` 192.168.5.1, `docker0` 172.17.0.1 (the gateway of my container) and a bridge for each extra Docker network, for example 192.168.49.1 for the minikube network.
