# Session 04: Networking Fundamentals

**Name:** Vansh Srivastava
**Enrollment No.:** 24bcs10567
**Session:** 04

Session 04 covered IP addressing (classes, subnet masks, network and host bits, private ranges), how a laptop gets an address with DHCP and reaches google.com through switches, routers and hops, and the Linux commands used to troubleshoot a network. For the homework I went through the networking repos shared in the course repo, practised subnetting with `ipcalc`, and ran the networking commands on Linux and macOS. All the command output with my explanations is in [networking-commands.md](networking-commands.md).

## Folder structure

```text
session-04-networking-fundamentals/
├── README.md                  # this file: Task 1 notes, Task 2 summary, what I learned
├── networking-commands.md     # Task 2: every command, its real output and my explanation
├── .gitignore
└── scripts/
    ├── lib.sh                 # run/block helpers: print "$ command", then its output
    ├── linux-commands.sh      # commands run in the Ubuntu 24.04 container
    └── mac-commands.sh        # commands run on the Mac and (read-only) in the Colima VM
```

## Environment

| Where | What | Used for |
|---|---|---|
| Mac | macOS 26.6.2, Apple Silicon, Wi-Fi `en0` 10.10.12.130/23 | real `ping` / `traceroute`, macOS versions of the tools |
| Colima VM | Ubuntu 24.04.4 with systemd, runs Docker | read-only checks (`ip -br addr`, `systemctl status`, DNS listener) |
| Ubuntu container | `s01-ubuntu`, Ubuntu 24.04.5 from `public.ecr.aws/docker/library/ubuntu:24.04`, root | all Linux commands (`ip`, `ss`, `dig`, `tcpdump`, ...) |

In the container I installed the tools with `apt-get install -y iproute2 iputils-ping iputils-tracepath traceroute dnsutils bind9-host curl wget net-tools netcat-openbsd telnet tcpdump ipcalc` (a minimal Ubuntu image has none of them). No host ports were published; everything ran inside the container or on the Mac.

How I ran the commands:

```bash
$ docker cp scripts s01-ubuntu:/root/s04
$ docker exec s01-ubuntu bash /root/s04/linux-commands.sh     # Linux commands
$ bash scripts/mac-commands.sh                                 # Mac + Colima VM commands
```

## Task 1: Practice the commands and repos shared in the devops-heros repo

The course repo (`session4-networking/resources.md`) links to the instructor's networking repos. I read them and practised what they describe:

| Repo / file | What it covers | What I practised |
|---|---|---|
| [Network-Troubleshooting](https://github.com/Nency-Ravaliya/Network-Troubleshooting) | Step-by-step checks for "google.com does not open": `ping`, `traceroute`, `netstat`, `telnet`, `tcpdump`, `nslookup`, `dig`, `curl`, `arp`, `systemctl` | ran every one of them (sections 5, 8-11, 13, 15 and 17-19 of [networking-commands.md](networking-commands.md)) |
| [Networking](https://github.com/Nency-Ravaliya/Networking) | DHCP (Discover, Offer, Request, Ack), what happens at each OSI layer when opening google.com, switch vs router vs hop | saw the real hops with `traceroute`, the ARP/MAC layer with `arp`, and the TCP three-way handshake with `tcpdump` |
| `session4-networking/ip.md` (session notes) | IP classes A-D, subnet mask, network and host bits, usable hosts = 2^host bits - 2, private ranges | checked the examples from the notes with `ipcalc` (below) |
| [Subnetting](https://github.com/Nency-Ravaliya/Subnetting) | splitting `192.168.1.0/24` into 4 subnets: borrow 2 bits, new mask /26, 64 addresses and 62 usable hosts per subnet | let `ipcalc` do the same split (below) |
| [IP-quest](https://github.com/Nency-Ravaliya/IP-quest) | four practice questions: highest host in a /24, host bits in 255.255.252.0, hosts with 255.255.248.0, usable IPs in a /21 | answered them by hand and checked with `ipcalc` (below) |
| [How-DHCP-Works](https://github.com/Nency-Ravaliya/How-DHCP-Works) | DHCP Discover, Offer, Request, Acknowledgement and the parameters a client gets (IP, mask, gateway, DNS) | looked at the DHCP ACK my Mac received (below) |
| [OSI-Network-devices](https://github.com/Nency-Ravaliya/OSI-Network-devices) | the OSI layers 1-7 for one web request, and which device works at which layer (switch at L2, router at L3) | matched layers to commands: `arp`/`ip neigh` (L2), `ip route`/`traceroute` (L3), `ss`/`nc`/`tcpdump` (L4), `dig`/`curl` (L7) |
| [IPFIX-NETFLOW-NTP](https://github.com/Nency-Ravaliya/IPFIX-NETFLOW-NTP) | flow-based traffic monitoring (NetFlow/IPFIX) and why NTP time sync matters for log timestamps | reading only (no flow collector here); the clock sync showed up in Session 02's journal as `SyncTime` lines |
| `session2-linux/Linux Networking Cheat Sheet.pdf` | `ip addr/link/route/neigh`, `ss`, and the old `net-tools` equivalents (`ifconfig`, `route`, `arp`, `netstat`) | ran both the `ip`/`ss` commands and their `net-tools` equivalents side by side |

### Subnetting practice with ipcalc

The session notes (`ip.md`) work through `197.23.45.10` with mask `255.255.255.0` and `120.27.1.0/8`. I checked them with `ipcalc` in the container:

```bash
$ ipcalc 197.23.45.10/24
Address:   197.23.45.10         11000101.00010111.00101101. 00001010
Netmask:   255.255.255.0 = 24   11111111.11111111.11111111. 00000000
Wildcard:  0.0.0.255            00000000.00000000.00000000. 11111111
=>
Network:   197.23.45.0/24       11000101.00010111.00101101. 00000000
HostMin:   197.23.45.1          11000101.00010111.00101101. 00000001
HostMax:   197.23.45.254        11000101.00010111.00101101. 11111110
Broadcast: 197.23.45.255        11000101.00010111.00101101. 11111111
Hosts/Net: 254                   Class C

$ ipcalc 120.27.1.0/8
Address:   120.27.1.0           01111000. 00011011.00000001.00000000
Netmask:   255.0.0.0 = 8        11111111. 00000000.00000000.00000000
Wildcard:  0.255.255.255        00000000. 11111111.11111111.11111111
=>
Network:   120.0.0.0/8          01111000. 00000000.00000000.00000000
HostMin:   120.0.0.1            01111000. 00000000.00000000.00000001
HostMax:   120.255.255.254      01111000. 11111111.11111111.11111110
Broadcast: 120.255.255.255      01111000. 11111111.11111111.11111111
Hosts/Net: 16777214              Class A
```

- `197.23.45.10/24`: Class C, network `197.23.45.0`, broadcast `197.23.45.255`, 8 host bits so 2^8 - 2 = 254 usable hosts. This matches the "197.23.45.10 - 255.255.255.0 - 197.23.45.255" line in the notes.
- `120.27.1.0/8`: Class A, 8 network bits and 24 host bits, so 2^24 - 2 = 16,777,214 usable hosts, network `120.0.0.0` to broadcast `120.255.255.255`, exactly as in the notes.

The Subnetting repo splits `192.168.1.0/24` into 4 subnets. Giving `ipcalc` the new prefix (26) lists them:

```bash
$ ipcalc -b 192.168.1.0/24 26
Address:   192.168.1.0          
Netmask:   255.255.255.0 = 24   
Wildcard:  0.0.0.255            
=>
Network:   192.168.1.0/24       
HostMin:   192.168.1.1          
HostMax:   192.168.1.254        
Broadcast: 192.168.1.255        
Hosts/Net: 254                   Class C, Private Internet

Subnets after transition from /24 to /26

Netmask:   255.255.255.192 = 26 
Wildcard:  0.0.0.63             

 1.
Network:   192.168.1.0/26       
HostMin:   192.168.1.1          
HostMax:   192.168.1.62         
Broadcast: 192.168.1.63         
Hosts/Net: 62                    Class C, Private Internet

 2.
Network:   192.168.1.64/26      
HostMin:   192.168.1.65         
HostMax:   192.168.1.126        
Broadcast: 192.168.1.127        
Hosts/Net: 62                    Class C, Private Internet

 3.
Network:   192.168.1.128/26     
HostMin:   192.168.1.129        
HostMax:   192.168.1.190        
Broadcast: 192.168.1.191        
Hosts/Net: 62                    Class C, Private Internet

 4.
Network:   192.168.1.192/26     
HostMin:   192.168.1.193        
HostMax:   192.168.1.254        
Broadcast: 192.168.1.255        
Hosts/Net: 62                    Class C, Private Internet


Subnets:   4
Hosts:     248
```

Same result as the repo: borrowing 2 bits (2^2 = 4 subnets) gives a /26 mask (255.255.255.192), 64 addresses per subnet, 62 usable, with networks .0, .64, .128, .192 and broadcasts .63, .127, .191, .255. In total 248 usable hosts instead of 254, because each extra subnet loses a network and a broadcast address.

The IP-quest questions, my answers, and the check:

| Question | My working | Answer |
|---|---|---|
| Highest host address in `192.168.0.0/24` | 8 host bits, broadcast is .255, so the last host is one below | `192.168.0.254` |
| Host bits in `255.255.252.0` | 252 = 11111100, so 8+8+6 = 22 network bits, 32 - 22 | 10 host bits (2^10 - 2 = 1022 hosts) |
| Total hosts with `255.255.248.0` | 248 = 11111000, so /21, 32 - 21 = 11 host bits, 2^11 = 2048 | 2048 addresses, 2046 usable |
| Usable IPs in a `/21` | same mask as the previous question | 2046 |

```bash
$ ipcalc -b 192.168.0.0/24 | grep -E "HostMin|HostMax|Broadcast"
HostMin:   192.168.0.1          
HostMax:   192.168.0.254        
Broadcast: 192.168.0.255        
$ ipcalc -b 10.0.0.0/255.255.252.0 | grep -E "Netmask|Hosts/Net"
Netmask:   255.255.252.0 = 22   
Hosts/Net: 1022                  Class A, Private Internet
$ ipcalc -b 10.0.0.0/255.255.248.0 | grep -E "Netmask|Hosts/Net"
Netmask:   255.255.248.0 = 21   
Hosts/Net: 2046                  Class A, Private Internet
$ ipcalc -b 10.0.0.0/21 | grep -E "Netmask|Hosts/Net"
Netmask:   255.255.248.0 = 21   
Hosts/Net: 2046                  Class A, Private Internet
```

The same idea applies to my own Wi-Fi network. macOS showed netmask `0xfffffe00` for `en0`, which is `/23`:

```bash
$ ipcalc -b 10.10.12.130/23
Address:   10.10.12.130         
Netmask:   255.255.254.0 = 23   
Wildcard:  0.0.1.255            
=>
Network:   10.10.12.0/23        
HostMin:   10.10.12.1           
HostMax:   10.10.13.254         
Broadcast: 10.10.13.255         
Hosts/Net: 510                   Class A, Private Internet
```

So my laptop is on a private /23 network (`10.0.0.0/8` range) that can hold 510 devices.

### DHCP: what my Mac received

The How-DHCP-Works repo explains DORA (Discover, Offer, Request, Acknowledgement). macOS keeps the last DHCP packet it received, so I could see the final step (the ACK) for my Wi-Fi:

```bash
$ ipconfig getpacket en0 | grep -E "^(op|yiaddr|dhcp_message_type|subnet_mask|router|domain_name_server|lease_time|server_identifier)"
op = BOOTREPLY
yiaddr = 10.10.12.130
options:
dhcp_message_type (uint8): ACK 0x5
subnet_mask (ip): 255.255.254.0
router (ip_mult): {10.10.12.1}
domain_name_server (ip_mult): {8.8.8.8}
lease_time (uint32): 0x15180
server_identifier (ip): 10.10.12.1
```

`op = BOOTREPLY` and message type `ACK` are the router's acknowledgement. `yiaddr` ("your IP address") is the address I was given, and the options are exactly the parameters the repo lists: subnet mask (255.255.254.0 = /23), router (default gateway 10.10.12.1), DNS server (8.8.8.8) and the lease time (0x15180 = 86400 seconds = 24 hours). `server_identifier` shows the router itself is the DHCP server. These are the same values `ifconfig`, `route get default` and `nslookup` show in networking-commands.md.

### Troubleshooting "google.com does not open", in order

Following the Network-Troubleshooting repo, this is the order I would use (each command is in networking-commands.md with real output):

1. `ip addr` / `hostname -I`: do I have an IP address at all?
2. `ip route`: do I have a default gateway?
3. `ping <gateway>` and `ip neigh` / `arp -n`: can I reach the gateway on the local network?
4. `cat /etc/resolv.conf`, `nslookup` / `dig` / `host google.com`: does DNS work? Try `dig @8.8.8.8` to rule out the local resolver.
5. `ping google.com`, `traceroute google.com`: is the server reachable, and where does the path stop?
6. `nc -zv google.com 443` or `telnet google.com 80`: is the port open?
7. `curl -v https://google.com`: do TLS and HTTP work?
8. `ss -tulnp` / `netstat -tulnp`: (for my own server) is the service listening on the right port and address?
9. `tcpdump`: what actually goes over the wire?
10. `systemctl status systemd-networkd` (or `NetworkManager`): is the network service itself running?

## Task 2: Markdown file with the commands, their output and my explanation

The file is **[networking-commands.md](networking-commands.md)**. It covers:

| # | Command(s) | Ran in | One-line summary |
|---|---|---|---|
| 1 | `hostname`, `hostname -I` | container, Mac | machine name and all its IPs |
| 2 | `ip addr`, `ip -br addr`, `ip -s link` | container | interfaces, addresses, MAC, MTU, traffic counters |
| 3 | `ifconfig`, `ipconfig getifaddr` | container, Mac | the older/macOS way to see interfaces |
| 4 | `ip route`, `ip route get`, `route -n`, `netstat -rn`, `route get default` | container, Mac | routing table and default gateway |
| 5 | `ip neigh`, `arp -n` | container, Mac | IP -> MAC cache for the local network |
| 6 | `/etc/hosts` | container | static name -> IP mappings checked before DNS |
| 7 | `/etc/resolv.conf`, `nsswitch.conf`, `getent hosts` | container, VM | which DNS server is used and in what order names are looked up |
| 8 | `ping` | Mac, container | ICMP reachability and latency |
| 9 | `traceroute`, `tracepath` | Mac, container | the routers (hops) on the way |
| 10 | `nslookup` | container, Mac | simple DNS query |
| 11 | `dig` | container | detailed DNS query, `+short`, `@server`, `-x` |
| 12 | `host` | container | short DNS lookups by record type |
| 13 | `curl` | container | HTTP(S) requests, headers, timing, TLS details |
| 14 | `wget` | container | download a file |
| 15 | `ss`, `netstat` | container, Mac | listening ports and the owning process |
| 16 | `nc` | container | tiny TCP server/client and port checks |
| 17 | `telnet` | container | raw TCP connection, hand-written HTTP request |
| 18 | `tcpdump` | container | captured the TCP handshake, HTTP request/response and close |
| 19 | `systemctl status systemd-networkd` | Colima VM | is the network service running |

The most interesting result: inside the container `ping google.com` "answered" in 0.1 ms, and even the unused documentation address 192.0.2.1 answered, while the Mac needed 17 to 103 ms for Google and got no reply from 192.0.2.1. The ICMP replies in the container are produced by the virtual network between the Colima VM and the Mac, not by the real hosts. TCP traffic (`curl`, `tcpdump`) does reach the real server, so for this kind of container a TCP check is the honest reachability test.

## What I learned

- A host needs four things to reach the internet: an IP address, a default gateway, a working DNS server, and ARP to find the gateway's MAC. Each has its own command (`ip addr`, `ip route`, `/etc/resolv.conf` + `dig`, `ip neigh`).
- The `ip` and `ss` commands replace `ifconfig`, `route`, `arp` and `netstat` on modern Linux, but the old ones are still common (and `ifconfig`/`netstat` are the normal tools on macOS), so it helps to know both.
- Subnet maths: host bits = 32 - prefix, usable hosts = 2^host bits - 2. `ipcalc` confirms it quickly.
- DNS problems can be isolated by asking a specific server (`dig @8.8.8.8`); here it showed that Colima's local DNS forwarder does not answer reverse lookups.
- A test is only as good as the path it takes. ICMP from a container behind a virtual network can be faked; TCP checks (`nc -z`, `curl`) and packet captures (`tcpdump`) show what really happens.
- `tcpdump` makes the theory visible: SYN, SYN-ACK, ACK, then the HTTP request and response, then FIN in both directions.
