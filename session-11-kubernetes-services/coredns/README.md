# Session 11, Task 4: CoreDNS

**Name:** Vansh Srivastava · **Enrollment No.:** 24bcs10567 · part of [Session 11](../README.md)

All output is from the shared minikube cluster (Kubernetes v1.37.0, CoreDNS v1.14.6). Test Pods ran in my namespaces `s11-services` and `s11-dns-client`. I only read CoreDNS's configuration and logs; I did not change anything in `kube-system`.

## What is CoreDNS?

CoreDNS is a small DNS server written in Go and built entirely from plugins (`kubernetes`, `forward`, `cache`, `log`, `health`, ...). It is a CNCF graduated project and has been the default cluster DNS in Kubernetes since v1.13, replacing the older kube-dns. In a cluster it runs as a normal Deployment in `kube-system`, behind a Service that is still called `kube-dns` for compatibility:

```bash
$ kubectl get deploy coredns -n kube-system -o wide
NAME      READY   UP-TO-DATE   AVAILABLE   AGE   CONTAINERS   IMAGES                                    SELECTOR
coredns   1/1     1            1           39m   coredns      registry.k8s.io/coredns/coredns:v1.14.6   k8s-app=kube-dns
$ kubectl get pods -n kube-system -l k8s-app=kube-dns -o wide
NAME                       READY   STATUS    RESTARTS   AGE   IP           NODE       NOMINATED NODE   READINESS GATES
coredns-559f6c778d-mb9q4   1/1     Running   0          39m   10.244.0.2   minikube   <none>           <none>
$ kubectl get svc kube-dns -n kube-system -o wide
NAME       TYPE        CLUSTER-IP   EXTERNAL-IP   PORT(S)                  AGE   SELECTOR
kube-dns   ClusterIP   10.96.0.10   <none>        53/UDP,53/TCP,9153/TCP   39m   k8s-app=kube-dns
$ kubectl get endpointslices -n kube-system -l kubernetes.io/service-name=kube-dns
NAME             ADDRESSTYPE   PORTS        ENDPOINTS    AGE
kube-dns-w6dcf   IPv4          53,53,9153   10.244.0.2   39m
```

Minikube runs one replica; production clusters usually run two or more (plus autoscaling) because every name lookup in the cluster depends on it.

## Why Kubernetes uses it

- **Service discovery by name.** Pods and Service IPs change; names do not. Apps connect to `orders.shop.svc.cluster.local` instead of an IP.
- **Always up to date.** CoreDNS watches the API server, so a new Service or a new ready Pod shows up in DNS within moments, with no DNS zone files to edit.
- **One resolver for everything.** The same server answers cluster names and forwards everything else (`example.com`) to upstream DNS.
- **Pluggable and observable.** Caching, logging, health checks and Prometheus metrics are all plugins configured in a single Corefile.

## How service discovery works

1. **kubelet points every Pod at CoreDNS.** The kubelet is configured with the cluster DNS IP and domain:

   ```bash
   $ minikube ssh -- "sudo grep -A1 -E 'clusterDNS|clusterDomain' /var/lib/kubelet/config.yaml"
   clusterDNS:
   - 10.96.0.10
   clusterDomain: cluster.local
   containerRuntimeEndpoint: unix:///run/containerd/containerd.sock
   $ kubectl get pod curl-client -n s11-services -o jsonpath='{.spec.dnsPolicy}{"\n"}'
   ClusterFirst
   ```

   With the default `dnsPolicy: ClusterFirst`, the kubelet writes `nameserver 10.96.0.10` (the `kube-dns` ClusterIP) and the namespace-specific search list into the Pod's `/etc/resolv.conf` (shown in the next section).

2. **CoreDNS's `kubernetes` plugin watches the API** for Services and EndpointSlices and builds the records on the fly: ClusterIP Services → their ClusterIP, headless Services → ready Pod IPs, ExternalName → CNAME. The [Session 11 README](../README.md) and [../fqdn/README.md](../fqdn/README.md) show real answers of each kind.

3. **The Pod connects to the answer.** For a ClusterIP, kube-proxy then load-balances to a Pod.

## How DNS queries are resolved: search domains and `ndots`

```bash
$ kubectl exec -n s11-dns-client dns-client -- cat /etc/resolv.conf
search s11-dns-client.svc.cluster.local svc.cluster.local cluster.local
nameserver 10.96.0.10
options ndots:5
```

- `nameserver 10.96.0.10`: every query goes to the `kube-dns` Service, which kube-proxy sends to a CoreDNS Pod.
- `search ...`: the suffixes the resolver appends to names that are not treated as complete. The first one is the Pod's own namespace.
- `options ndots:5`: a name with **fewer than 5 dots** is first tried with each search suffix, and only then as written. A name ending with a dot is always treated as complete.

Minikube's Corefile has the `log` plugin enabled, so CoreDNS logs every query it receives. I used that to watch exactly what one lookup turns into. The debug Pod `dnsutils` ([dnsutils.yaml](dnsutils.yaml), image from the official Kubernetes DNS debugging guide) has IP `10.244.0.254`, so I filtered the CoreDNS log by that IP. The query IDs in the log match the `id:` values that `dig` prints.

**Cross-namespace name `web-service-clusterip.s11-services` (1 dot < 5):**

```bash
$ kubectl exec -n s11-dns-client dnsutils -- dig +search +showsearch +noall +answer +comments web-service-clusterip.s11-services | grep -E 'status|IN A'
;; ->>HEADER<<- opcode: QUERY, status: NXDOMAIN, id: 21554
;; ->>HEADER<<- opcode: QUERY, status: NOERROR, id: 44903
web-service-clusterip.s11-services.svc.cluster.local. 30 IN A 10.96.103.40
$ sleep 2; kubectl logs -n kube-system deploy/coredns --since=30s | grep '10.244.0.254' | grep 'web-service-clusterip'
[INFO] 10.244.0.254:56007 - 16490 "A IN web-service-clusterip.s11-services.s11-dns-client.svc.cluster.local. udp 96 false 4096" NXDOMAIN qr,aa,rd 178 0.000170263s
[INFO] 10.244.0.254:52266 - 19 "A IN web-service-clusterip.s11-services.svc.cluster.local. udp 81 false 4096" NOERROR qr,aa,rd 138 0.000139428s
[INFO] 10.244.0.254:32777 - 21554 "A IN web-service-clusterip.s11-services.s11-dns-client.svc.cluster.local. udp 96 false 4096" NXDOMAIN qr,aa,rd 178 0.000132623s
[INFO] 10.244.0.254:41310 - 44903 "A IN web-service-clusterip.s11-services.svc.cluster.local. udp 81 false 4096" NOERROR qr,aa,rd 138 0.000059115s
```

(The first two log lines, ids 16490 and 19, are from an identical test I ran a minute earlier.) The resolver first appended the client's own namespace (`...s11-dns-client.svc.cluster.local`, NXDOMAIN), then `svc.cluster.local`, which matched. Two queries for one lookup.

**External name `example.com` (1 dot < 5):**

```bash
$ kubectl exec -n s11-dns-client dnsutils -- dig +search +showsearch +noall +answer +comments example.com | grep -E 'status|IN A'
;; ->>HEADER<<- opcode: QUERY, status: NXDOMAIN, id: 5313
;; ->>HEADER<<- opcode: QUERY, status: NXDOMAIN, id: 35956
;; ->>HEADER<<- opcode: QUERY, status: NXDOMAIN, id: 20027
;; ->>HEADER<<- opcode: QUERY, status: NOERROR, id: 43234
$ sleep 2; kubectl logs -n kube-system deploy/coredns --since=30s | grep '10.244.0.254' | grep 'example.com'
[INFO] 10.244.0.254:46653 - 5313 "A IN example.com.s11-dns-client.svc.cluster.local. udp 73 false 4096" NXDOMAIN qr,aa,rd 155 0.00014406s
[INFO] 10.244.0.254:42663 - 35956 "A IN example.com.svc.cluster.local. udp 58 false 4096" NXDOMAIN qr,aa,rd 140 0.000041583s
[INFO] 10.244.0.254:54758 - 20027 "A IN example.com.cluster.local. udp 54 false 4096" NXDOMAIN qr,aa,rd 136 0.000027278s
[INFO] 10.244.0.254:35629 - 43234 "A IN example.com. udp 40 false 4096" NOERROR qr,rd,ra 83 0.003175951s
```

Because of `ndots:5`, looking up `example.com` costs **four** queries: three guaranteed NXDOMAINs inside `cluster.local`, then the real one, which CoreDNS forwarded upstream (`ra` = recursion available, not `aa` = authoritative).

**The same name with a trailing dot (an absolute name):**

```bash
$ kubectl exec -n s11-dns-client dnsutils -- dig +search +noall +answer example.com.
example.com.		3	IN	A	172.66.147.243
example.com.		3	IN	A	104.20.23.154
$ sleep 2; kubectl logs -n kube-system deploy/coredns --since=5s | grep '10.244.0.254' | grep 'example.com'
...
[INFO] 10.244.0.254:42517 - 1703 "A IN example.com. udp 40 false 4096" NOERROR qr,aa,rd,ra 83 0.000058802s
```

One query, no search list, and it was answered from CoreDNS's cache in 0.06 ms. This is why apps that call many external hosts sometimes use FQDNs with a trailing dot, or lower `ndots` in the Pod's `dnsConfig`.

## CoreDNS configuration: the real Corefile

The configuration lives in the `coredns` ConfigMap in `kube-system`:

```bash
$ kubectl get configmap coredns -n kube-system -o jsonpath='{.data.Corefile}'
.:53 {
    log
    errors
    health {
       lameduck 5s
    }
    ready
    kubernetes cluster.local in-addr.arpa ip6.arpa {
       pods insecure
       fallthrough in-addr.arpa ip6.arpa
       ttl 30
    }
    prometheus :9153
    hosts {
       192.168.5.2 host.minikube.internal
       fallthrough
    }
    forward . /etc/resolv.conf {
       max_concurrent 1000
    }
    cache 30 {
       disable success cluster.local
       disable denial cluster.local
    }
    loop
    reload
    loadbalance
}
```

| Line | What it does |
| --- | --- |
| `.:53 { ... }` | one server block for all zones (`.`) on port 53 |
| `log` | logs every query (minikube adds this; the stock kubeadm Corefile does not have it). This is what made the query log above possible |
| `errors` | logs errors to stdout |
| `health { lameduck 5s }` | `http://<pod>:8080/health`; on shutdown keeps answering for 5 s so clients can move away |
| `ready` | `http://<pod>:8181/ready`, used by the Pod's readiness probe |
| `kubernetes cluster.local in-addr.arpa ip6.arpa` | answers cluster names and reverse lookups from the Kubernetes API |
| `pods insecure` | enables `a-b-c-d.<ns>.pod.cluster.local` records without checking the Pod exists |
| `fallthrough in-addr.arpa ip6.arpa` | reverse lookups it cannot answer go to the next plugin |
| `ttl 30` | TTL of the records it generates (the `30` in the dig answers) |
| `prometheus :9153` | metrics endpoint (port 9153 of the `kube-dns` Service) |
| `hosts { 192.168.5.2 host.minikube.internal ... }` | minikube-specific static entry so Pods can reach the host |
| `forward . /etc/resolv.conf` | everything else goes to the node's upstream resolvers |
| `cache 30 { disable success/denial cluster.local }` | caches external answers up to 30 s, but not cluster names, so Service changes show up immediately |
| `loop` | detects forwarding loops and stops CoreDNS instead of looping forever |
| `reload` | picks up ConfigMap changes without a restart |
| `loadbalance` | shuffles the order of A records in each answer |

## How to troubleshoot DNS issues

The order I would check things in, with the real commands:

**1. Is CoreDNS running and behind its Service?** (shown at the top: Pod `1/1 Running`, `kube-dns` has endpoint `10.244.0.2`). No endpoints means every lookup in the cluster times out.

**2. Does the Pod use the right resolver?** Check `/etc/resolv.conf` and `dnsPolicy` (shown above).

**3. Can a debug Pod resolve a name that always exists?**

```bash
$ kubectl exec -n s11-dns-client dnsutils -- nslookup kubernetes.default
Server:		10.96.0.10
Address:	10.96.0.10#53

Name:	kubernetes.default.svc.cluster.local
Address: 10.96.0.1

```

**4. Ask the CoreDNS Pod directly** (bypasses the Service and kube-proxy, so it separates "CoreDNS is broken" from "the path to CoreDNS is broken"), and check its health, readiness and metrics endpoints:

```bash
$ kubectl exec -n s11-dns-client dnsutils -- dig +short @10.244.0.2 kubernetes.default.svc.cluster.local
10.96.0.1
$ kubectl exec -n s11-services curl-client -- curl -s http://10.244.0.2:8080/health; echo
OK
$ kubectl exec -n s11-services curl-client -- curl -s http://10.244.0.2:8181/ready; echo
OK
$ kubectl exec -n s11-services curl-client -- curl -s http://10.244.0.2:9153/metrics | grep -E '^coredns_dns_responses_total' | head -6
coredns_dns_responses_total{plugin="errors",rcode="NOERROR",server="dns://:53",view="",zone="."} 694207
coredns_dns_responses_total{plugin="errors",rcode="NXDOMAIN",server="dns://:53",view="",zone="."} 1705
```

The counters are cluster-wide (every tenant on this shared cluster). A sudden rise in `SERVFAIL` here would point at upstream or plugin problems.

**5. Read the CoreDNS logs.** `kubectl logs -n kube-system deploy/coredns` shows `[ERROR]` lines (for example upstream timeouts or a detected loop) and, with the `log` plugin, every query with its client IP and result, as used in the ndots section. One thing that tripped me up: `kubectl logs -l k8s-app=kube-dns` only returns the last 10 lines per Pod by default when a label selector is used, so I switched to `deploy/coredns`, which returns the full log.

**6. Typical misconfigurations.** I reproduced one on purpose: [broken-dns-pod.yaml](broken-dns-pod.yaml) uses `dnsPolicy: None` with a nameserver where nothing listens.

```bash
$ kubectl apply -f coredns/broken-dns-pod.yaml
pod/broken-dns created
$ kubectl wait -n s11-dns-client --for=condition=Ready pod/broken-dns --timeout=120s
pod/broken-dns condition met
$ kubectl exec -n s11-dns-client broken-dns -- cat /etc/resolv.conf
search s11-dns-client.svc.cluster.local svc.cluster.local cluster.local
nameserver 10.96.0.99
options ndots:5
$ kubectl exec -n s11-dns-client broken-dns -- nslookup -timeout=2 web-service-clusterip.s11-services.svc.cluster.local; echo "exit code: $?"
;; connection timed out; no servers could be reached

command terminated with exit code 1
exit code: 1
$ kubectl exec -n s11-dns-client broken-dns -- curl -s --max-time 15 -o /dev/null http://web-service-clusterip.s11-services:8080; echo "curl exit code: $?"
command terminated with exit code 6
curl exit code: 6
$ kubectl exec -n s11-dns-client broken-dns -- curl -s -o /dev/null -w 'by IP: HTTP %{http_code}\n' http://10.96.103.40:8080
by IP: HTTP 200
$ kubectl get pod broken-dns -n s11-dns-client -o jsonpath='{.spec.dnsPolicy} {.spec.dnsConfig.nameservers}{"\n"}'
None ["10.96.0.99"]
```

The symptom is a **timeout** ("no servers could be reached"), not NXDOMAIN. Connecting by IP still works, which proves the network is fine and the problem is DNS only. The fix is to remove the custom `dnsPolicy`/`dnsConfig` (or point it at `10.96.0.10`).

### Symptom → likely cause

| Symptom | Likely cause | Check |
| --- | --- | --- |
| `NXDOMAIN` for a Service name | wrong namespace in the name, typo, or the Service does not exist | `kubectl get svc -n <ns>`, use `svc.namespace` ([../fqdn/README.md](../fqdn/README.md)) |
| Name resolves but connection refused | Service has no endpoints (selector mismatch, Pods not ready) | `kubectl get endpointslices -l kubernetes.io/service-name=<svc>` (drill in the [Session 11 README](../README.md)) |
| "connection timed out; no servers could be reached" | CoreDNS down or no endpoints, wrong `nameserver` (custom dnsPolicy), NetworkPolicy blocking UDP/TCP 53 | steps 1, 2 and 4 above |
| Cluster names work, external names fail | upstream resolver problem, `forward` misconfigured | CoreDNS `[ERROR]` logs, `dig @10.244.0.2 example.com` |
| CoreDNS Pods in CrashLoopBackOff with a "Loop ... detected" error | the node's `/etc/resolv.conf` points back at CoreDNS (for example 127.0.0.53) | `kubectl logs -n kube-system deploy/coredns`, fix the upstream in `forward` |
| Slow lookups for external names | `ndots:5` search expansion (four queries per lookup, as shown above) | use FQDNs with a trailing dot, or set `ndots` lower in `dnsConfig` |
