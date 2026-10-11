# Session 11, Task 3: FQDN and Service DNS in Kubernetes

**Name:** Vansh Srivastava · **Enrollment No.:** 24bcs10567 · part of [Session 11](../README.md)

All lookups below are real and were run from client Pods in two namespaces:

- `s11-services`: where the Services live (`web-service-clusterip`, `web-service-headless` with StatefulSet `web-stateful`, and the client Pod `curl-client`), see the [Session 11 README](../README.md).
- `s11-dns-client`: a second namespace created by [dns-client.yaml](dns-client.yaml) (`dns-client`, which has curl and busybox `nslookup`) and [../coredns/dnsutils.yaml](../coredns/dnsutils.yaml) (`dnsutils`, which has `dig`).

```bash
$ kubectl apply -f fqdn/dns-client.yaml -f coredns/dnsutils.yaml
namespace/s11-dns-client created
pod/dns-client created
pod/dnsutils created
$ kubectl wait -n s11-dns-client --for=condition=Ready pod --all --timeout=180s
pod/dns-client condition met
pod/dnsutils condition met
$ kubectl get pods -n s11-dns-client -o wide
NAME         READY   STATUS    RESTARTS   AGE   IP             NODE       NOMINATED NODE   READINESS GATES
dns-client   1/1     Running   0          0s    10.244.0.253   minikube   <none>           <none>
dnsutils     1/1     Running   0          0s    10.244.0.254   minikube   <none>           <none>
```

## What is an FQDN?

A **Fully Qualified Domain Name** is the complete name of a host, from the host label up to the root of the DNS tree, so it cannot be ambiguous: `www.example.com.` (the trailing dot is the root). A short name like `www` only works if the resolver adds the rest for you from a **search list**.

In Kubernetes every Service (and every Pod) gets a name under the cluster domain, `cluster.local` by default. That gives apps a stable address that does not depend on Pod IPs.

## Kubernetes Service DNS and the naming convention

| Record | Name format | Answer |
| --- | --- | --- |
| Normal Service (ClusterIP) | `<service>.<namespace>.svc.cluster.local` | A record → the Service's ClusterIP |
| Headless Service | `<service>.<namespace>.svc.cluster.local` | A records → every ready Pod IP |
| Pod behind a headless Service (StatefulSet) | `<pod-hostname>.<service>.<namespace>.svc.cluster.local` | A record → that Pod's IP |
| Named port | `_<port-name>._<protocol>.<service>.<namespace>.svc.cluster.local` | SRV records (port + target names) |
| Any Pod | `<pod-ip-with-dashes>.<namespace>.pod.cluster.local` | A record → that Pod IP |
| ExternalName Service | `<service>.<namespace>.svc.cluster.local` | CNAME → the external name |
| Reverse lookup | `<ip reversed>.in-addr.arpa` | PTR → the Service FQDN |

Read right to left: `cluster.local` (cluster domain) → `svc` (the Service zone) → namespace → Service name.

### Service A record

```bash
$ kubectl exec -n s11-dns-client dnsutils -- dig +noall +answer web-service-clusterip.s11-services.svc.cluster.local
web-service-clusterip.s11-services.svc.cluster.local. 30 IN A 10.96.103.40
$ kubectl exec -n s11-dns-client dnsutils -- dig +noall +answer -x 10.96.103.40
40.103.96.10.in-addr.arpa. 30	IN	PTR	web-service-clusterip.s11-services.svc.cluster.local.
```

One A record with the ClusterIP and a 30-second TTL. The reverse lookup maps the ClusterIP back to the Service FQDN.

### Pod DNS (A record per Pod IP)

```bash
$ kubectl get pod curl-client -n s11-services -o jsonpath='{.status.podIP}{"\n"}'
10.244.0.203
$ kubectl exec -n s11-dns-client dnsutils -- dig +noall +answer 10-244-0-203.s11-services.pod.cluster.local
10-244-0-203.s11-services.pod.cluster.local. 30	IN A 10.244.0.203
```

The Pod IP with dashes instead of dots, under `<namespace>.pod.cluster.local`. These names are only as stable as the Pod IP, so they are rarely useful except for things like TLS certificates. (CoreDNS answers them because the Corefile has `pods insecure`, see [../coredns/README.md](../coredns/README.md).)

### Headless Service: per-Pod records and SRV records

```bash
$ kubectl exec -n s11-dns-client dnsutils -- dig +noall +answer web-service-headless.s11-services.svc.cluster.local
web-service-headless.s11-services.svc.cluster.local. 30	IN A 10.244.0.223
web-service-headless.s11-services.svc.cluster.local. 30	IN A 10.244.0.224
web-service-headless.s11-services.svc.cluster.local. 30	IN A 10.244.0.222
$ kubectl exec -n s11-dns-client dnsutils -- dig +noall +answer web-stateful-2.web-service-headless.s11-services.svc.cluster.local
web-stateful-2.web-service-headless.s11-services.svc.cluster.local. 30 IN A 10.244.0.224
$ kubectl exec -n s11-dns-client dnsutils -- dig +noall +answer SRV _web._tcp.web-service-headless.s11-services.svc.cluster.local
_web._tcp.web-service-headless.s11-services.svc.cluster.local. 30 IN SRV 0 33 80 web-stateful-0.web-service-headless.s11-services.svc.cluster.local.
_web._tcp.web-service-headless.s11-services.svc.cluster.local. 30 IN SRV 0 33 80 web-stateful-1.web-service-headless.s11-services.svc.cluster.local.
_web._tcp.web-service-headless.s11-services.svc.cluster.local. 30 IN SRV 0 33 80 web-stateful-2.web-service-headless.s11-services.svc.cluster.local.
$ kubectl exec -n s11-dns-client dns-client -- curl -s http://web-stateful-2.web-service-headless.s11-services
served by web-stateful-2
$ kubectl exec -n s11-services web-stateful-0 -- cat /etc/hosts | tail -2
fe00::2	ip6-allrouters
10.244.0.222	web-stateful-0.web-service-headless.s11-services.svc.cluster.local	web-stateful-0
```

- The headless name returns all three Pod IPs (no ClusterIP in between).
- Each StatefulSet Pod has its own stable name `web-stateful-N.web-service-headless...`; I reached Pod 2 directly from the other namespace.
- The SRV query uses the port name (`web`) and protocol: priority 0, weight 33 each, port 80, target = the per-Pod name.
- Inside the Pod, the kubelet writes the Pod's own FQDN into `/etc/hosts`, because the StatefulSet sets `hostname` and `subdomain` on it.

## Namespace-based DNS

Every Pod's `/etc/resolv.conf` is written by the kubelet, and the **first search domain is the Pod's own namespace**:

```bash
$ kubectl exec -n s11-services curl-client -- cat /etc/resolv.conf
search s11-services.svc.cluster.local svc.cluster.local cluster.local
nameserver 10.96.0.10
options ndots:5
$ kubectl exec -n s11-dns-client dns-client -- cat /etc/resolv.conf
search s11-dns-client.svc.cluster.local svc.cluster.local cluster.local
nameserver 10.96.0.10
options ndots:5
```

So the same short name means different things in different namespaces:

| Name used by the client | From `s11-services` | From `s11-dns-client` |
| --- | --- | --- |
| `web-service-clusterip` | works (expands to `...s11-services.svc.cluster.local`) | fails (expands to `...s11-dns-client.svc.cluster.local`, which does not exist) |
| `web-service-clusterip.s11-services` | works | works (second search domain `svc.cluster.local` completes it) |
| `web-service-clusterip.s11-services.svc.cluster.local` | works | works |

**Same namespace: the short name works.**

```bash
$ kubectl exec -n s11-services curl-client -- curl -s -o /dev/null -w 'short name from s11-services: HTTP %{http_code} (%{remote_ip})\n' http://web-service-clusterip:8080
short name from s11-services: HTTP 200 (10.96.103.40)
```

This busybox `nslookup` of the short name (run during the Service tests) shows the search list in action. It tried the name with every search domain, and only `...s11-services.svc.cluster.local` exists:

```bash
$ kubectl exec -n s11-services curl-client -- nslookup web-service-clusterip
Server:		10.96.0.10
Address:	10.96.0.10:53

** server can't find web-service-clusterip.cluster.local: NXDOMAIN

Name:	web-service-clusterip.s11-services.svc.cluster.local
Address: 10.96.103.40

** server can't find web-service-clusterip.svc.cluster.local: NXDOMAIN

** server can't find web-service-clusterip.cluster.local: NXDOMAIN


** server can't find web-service-clusterip.svc.cluster.local: NXDOMAIN

command terminated with exit code 1
```

(busybox prints every NXDOMAIN and returns exit code 1 even though one answer was found.)

**Other namespace: the short name fails; `svc.namespace` and the full FQDN work.**

```bash
$ kubectl exec -n s11-dns-client dns-client -- curl -s --max-time 5 -o /dev/null http://web-service-clusterip:8080; echo "short name from s11-dns-client: curl exit code $?"
command terminated with exit code 6
short name from s11-dns-client: curl exit code 6
$ kubectl exec -n s11-dns-client dns-client -- nslookup web-service-clusterip.s11-dns-client.svc.cluster.local
Server:		10.96.0.10
Address:	10.96.0.10:53

** server can't find web-service-clusterip.s11-dns-client.svc.cluster.local: NXDOMAIN

** server can't find web-service-clusterip.s11-dns-client.svc.cluster.local: NXDOMAIN

command terminated with exit code 1
$ kubectl exec -n s11-dns-client dns-client -- curl -s -o /dev/null -w 'svc.namespace: HTTP %{http_code} (%{remote_ip})\n' http://web-service-clusterip.s11-services:8080
svc.namespace: HTTP 200 (10.96.103.40)
$ kubectl exec -n s11-dns-client dns-client -- curl -s -o /dev/null -w 'full FQDN: HTTP %{http_code} (%{remote_ip})\n' http://web-service-clusterip.s11-services.svc.cluster.local:8080
full FQDN: HTTP 200 (10.96.103.40)
$ kubectl exec -n s11-dns-client dns-client -- nslookup web-service-clusterip.s11-services.svc.cluster.local
Server:		10.96.0.10
Address:	10.96.0.10:53


Name:	web-service-clusterip.s11-services.svc.cluster.local
Address: 10.96.103.40

$ kubectl exec -n s11-dns-client dns-client -- nslookup kubernetes.default.svc.cluster.local
Server:		10.96.0.10
Address:	10.96.0.10:53

Name:	kubernetes.default.svc.cluster.local
Address: 10.96.0.1
```

From `s11-dns-client`, the short name became `web-service-clusterip.s11-dns-client.svc.cluster.local`, which does not exist (NXDOMAIN, curl exit 6 = could not resolve host). Adding the namespace fixed it. The API server is always reachable as `kubernetes.default.svc.cluster.local` from any namespace.

## Pod-to-Service communication

1. The app calls `http://web-service-clusterip.s11-services:8080`.
2. The C library resolver reads `/etc/resolv.conf`: the name has fewer than 5 dots (`ndots:5`), so it tries the search domains first and sends the queries to `10.96.0.10` (the `kube-dns` Service, i.e. CoreDNS).
3. CoreDNS answers `web-service-clusterip.s11-services.svc.cluster.local → 10.96.103.40` from its watch of Services and EndpointSlices.
4. The app connects to `10.96.103.40:8080`. kube-proxy's iptables rules on the node pick one ready Pod and DNAT the connection to `PodIP:80` (the rules are shown in [../object-comparison/README.md](../object-comparison/README.md#how-traffic-reaches-the-pods)).

For a headless Service, step 4 is skipped: DNS already returned Pod IPs, so the client connects to a Pod directly.

**Practical rule I follow:** inside the same namespace use the short name; across namespaces use at least `service.namespace`. In config files that may be read from any namespace, use the full `service.namespace.svc.cluster.local` (adding a trailing dot avoids the search-list lookups described in the CoreDNS README).
