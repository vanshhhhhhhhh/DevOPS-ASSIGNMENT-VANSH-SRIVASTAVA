# Session 11, Task 2: Kubernetes object comparison

**Name:** Vansh Srivastava · **Enrollment No.:** 24bcs10567 · part of [Session 11](../README.md)

To back the comparison with real output, I deployed one of each object into namespace `s11-compare` from the YAML files in this folder:

| File | Object |
| --- | --- |
| [deployment.yaml](deployment.yaml) | Deployment `cmp-deploy`, 2 replicas, nginx 1.24 |
| [replicaset.yaml](replicaset.yaml) | bare ReplicaSet `cmp-rs`, 2 replicas, nginx 1.24 (no Deployment on top) |
| [daemonset.yaml](daemonset.yaml) | DaemonSet `cmp-ds`, a busybox "agent" that prints its node name |
| [statefulset.yaml](statefulset.yaml) | StatefulSet `cmp-sts`, 2 replicas, its headless Service and a 16Mi PVC per Pod |
| [service.yaml](service.yaml) | ClusterIP Service `cmp-deploy-svc` in front of the Deployment's Pods |

```bash
$ kubectl create namespace s11-compare
namespace/s11-compare created
$ kubectl apply -n s11-compare -f object-comparison/
daemonset.apps/cmp-ds created
deployment.apps/cmp-deploy created
replicaset.apps/cmp-rs created
service/cmp-deploy-svc created
service/cmp-sts created
statefulset.apps/cmp-sts created
$ kubectl wait -n s11-compare --for=condition=Ready pod --all --timeout=120s >/dev/null; kubectl get deploy,rs,sts,ds,pods,svc,pvc -n s11-compare
NAME                         READY   UP-TO-DATE   AVAILABLE   AGE
deployment.apps/cmp-deploy   2/2     2            2           2s

NAME                                    DESIRED   CURRENT   READY   AGE
replicaset.apps/cmp-deploy-6685fc4b94   2         2         2       2s
replicaset.apps/cmp-rs                  2         2         2       2s

NAME                       READY   AGE
statefulset.apps/cmp-sts   2/2     2s

NAME                    DESIRED   CURRENT   READY   UP-TO-DATE   AVAILABLE   NODE SELECTOR   AGE
daemonset.apps/cmp-ds   1         1         1       1            1           <none>          2s

NAME                              READY   STATUS    RESTARTS   AGE
pod/cmp-deploy-6685fc4b94-jpbzh   1/1     Running   0          2s
pod/cmp-deploy-6685fc4b94-lj9kk   1/1     Running   0          2s
pod/cmp-ds-tccbs                  1/1     Running   0          2s
pod/cmp-rs-29fbp                  1/1     Running   0          2s
pod/cmp-rs-pp7j4                  1/1     Running   0          2s
pod/cmp-sts-0                     1/1     Running   0          2s
pod/cmp-sts-1                     1/1     Running   0          1s

NAME                     TYPE        CLUSTER-IP       EXTERNAL-IP   PORT(S)   AGE
service/cmp-deploy-svc   ClusterIP   10.106.220.180   <none>        80/TCP    2s
service/cmp-sts          ClusterIP   None             <none>        80/TCP    2s

NAME                                   STATUS   VOLUME                                     CAPACITY   ACCESS MODES   STORAGECLASS   VOLUMEATTRIBUTESCLASS   AGE
persistentvolumeclaim/data-cmp-sts-0   Bound    pvc-6c0af8ef-b48e-4cdb-af6f-8385e45adc43   16Mi       RWO            standard       <unset>                 2s
persistentvolumeclaim/data-cmp-sts-1   Bound    pvc-d81e1843-7045-4f72-a973-f7433dc9f250   16Mi       RWO            standard       <unset>                 1s
```

Already visible: the Deployment created a ReplicaSet with a hash in its name (`cmp-deploy-6685fc4b94`), the bare ReplicaSet has no hash, the StatefulSet Pods are numbered (`-0`, `-1`) and each has its own PVC, and the DaemonSet has DESIRED = 1 because there is one node.

---

## 1. Deployment vs ReplicaSet

| | ReplicaSet | Deployment |
| --- | --- | --- |
| Purpose | Keep N identical Pods running | Manage the rollout of a Pod template over time (on top of ReplicaSets) |
| Pod management | Creates and deletes Pods directly to match `replicas` | Never touches Pods itself: it creates/scales ReplicaSets, which manage the Pods |
| Scaling | `kubectl scale rs` | `kubectl scale deploy` (it scales its current ReplicaSet) |
| Rolling updates | **None.** Changing the template affects only Pods created later | Yes: new ReplicaSet per template change, maxSurge/maxUnavailable, pause/resume |
| Rollback / history | None | `kubectl rollout undo`, `rollout history` (old ReplicaSets kept at 0) |
| Relationship | Owned by a Deployment (normal case) or standalone | Owns one ReplicaSet per revision |
| When to use it directly | Almost never | Default for stateless apps |

### Relationship: owner references

Every Pod and ReplicaSet records its owner in `metadata.ownerReferences`. The garbage collector uses this to delete children when the owner is deleted.

```bash
$ kubectl get pods -n s11-compare -o custom-columns=POD:.metadata.name,OWNER-KIND:.metadata.ownerReferences[0].kind,OWNER-NAME:.metadata.ownerReferences[0].name,CONTROLLER:.metadata.ownerReferences[0].controller
POD                           OWNER-KIND    OWNER-NAME              CONTROLLER
cmp-deploy-6685fc4b94-jpbzh   ReplicaSet    cmp-deploy-6685fc4b94   true
cmp-deploy-6685fc4b94-lj9kk   ReplicaSet    cmp-deploy-6685fc4b94   true
cmp-ds-tccbs                  DaemonSet     cmp-ds                  true
cmp-rs-29fbp                  ReplicaSet    cmp-rs                  true
cmp-rs-pp7j4                  ReplicaSet    cmp-rs                  true
cmp-sts-0                     StatefulSet   cmp-sts                 true
cmp-sts-1                     StatefulSet   cmp-sts                 true
$ kubectl get rs -n s11-compare -o custom-columns=REPLICASET:.metadata.name,OWNER-KIND:.metadata.ownerReferences[0].kind,OWNER-NAME:.metadata.ownerReferences[0].name
REPLICASET              OWNER-KIND   OWNER-NAME
cmp-deploy-6685fc4b94   Deployment   cmp-deploy
cmp-rs                  <none>       <none>
$ kubectl get rs -n s11-compare -l app=cmp-deploy -o yaml | grep -A6 ownerReferences
    ownerReferences:
    - apiVersion: apps/v1
      blockOwnerDeletion: true
      controller: true
      kind: Deployment
      name: cmp-deploy
      uid: 45788688-66aa-4d47-bbf3-a54d7095dd3f
```

So the chain is **Deployment `cmp-deploy` → ReplicaSet `cmp-deploy-6685fc4b94` → Pods**. The bare `cmp-rs` has no owner. DaemonSet and StatefulSet Pods are owned directly by their controller, with no ReplicaSet in between.

### Rolling updates: the real difference

Changing the image of the **bare ReplicaSet** changes nothing for the running Pods. Only a Pod created after the change (here, after I deleted one) gets the new image, so the ReplicaSet ends up running two versions at once:

```bash
$ kubectl set image rs/cmp-rs web=public.ecr.aws/docker/library/nginx:1.25-alpine -n s11-compare
replicaset.apps/cmp-rs image updated
$ sleep 5; kubectl get pods -n s11-compare -l app=cmp-rs -o custom-columns=POD:.metadata.name,IMAGE:.spec.containers[0].image
POD            IMAGE
cmp-rs-29fbp   public.ecr.aws/docker/library/nginx:1.24-alpine
cmp-rs-h7lb5   public.ecr.aws/docker/library/nginx:1.24-alpine
cmp-rs-pp7j4   public.ecr.aws/docker/library/nginx:1.24-alpine
$ kubectl delete pod -n s11-compare $(kubectl get pods -n s11-compare -l app=cmp-rs -o jsonpath='{.items[0].metadata.name}')
pod "cmp-rs-29fbp" deleted from s11-compare namespace
$ sleep 3; kubectl get pods -n s11-compare -l app=cmp-rs -o custom-columns=POD:.metadata.name,IMAGE:.spec.containers[0].image
POD            IMAGE
cmp-rs-h7lb5   public.ecr.aws/docker/library/nginx:1.24-alpine
cmp-rs-mlclx   public.ecr.aws/docker/library/nginx:1.25-alpine
cmp-rs-pp7j4   public.ecr.aws/docker/library/nginx:1.24-alpine
```

The same change on the **Deployment** triggers a proper rollout: a new ReplicaSet is created and the Pods are replaced step by step, while the old ReplicaSet is kept at 0 for rollback:

```bash
$ kubectl set image deployment/cmp-deploy web=public.ecr.aws/docker/library/nginx:1.25-alpine -n s11-compare
deployment.apps/cmp-deploy image updated
$ kubectl rollout status deployment/cmp-deploy -n s11-compare --timeout=120s
Waiting for deployment "cmp-deploy" rollout to finish: 1 out of 3 new replicas have been updated...
...
Waiting for deployment "cmp-deploy" rollout to finish: 1 old replicas are pending termination...
deployment "cmp-deploy" successfully rolled out
$ kubectl get rs -n s11-compare -l app=cmp-deploy -o custom-columns=REPLICASET:.metadata.name,DESIRED:.spec.replicas,READY:.status.readyReplicas,IMAGE:.spec.template.spec.containers[0].image
REPLICASET              DESIRED   READY    IMAGE
cmp-deploy-568c74d47f   3         3        public.ecr.aws/docker/library/nginx:1.25-alpine
cmp-deploy-6685fc4b94   0         <none>   public.ecr.aws/docker/library/nginx:1.24-alpine
$ sleep 3; kubectl get pods -n s11-compare -l app=cmp-deploy -o custom-columns=POD:.metadata.name,IMAGE:.spec.containers[0].image
POD                           IMAGE
cmp-deploy-568c74d47f-9vrx4   public.ecr.aws/docker/library/nginx:1.25-alpine
cmp-deploy-568c74d47f-dr42w   public.ecr.aws/docker/library/nginx:1.25-alpine
cmp-deploy-568c74d47f-vnxhp   public.ecr.aws/docker/library/nginx:1.25-alpine
```

(Both had been scaled to 3 replicas in the scaling test below before this step.)

---

## 2. Deployment vs DaemonSet vs StatefulSet

| | Deployment | DaemonSet | StatefulSet |
| --- | --- | --- | --- |
| Use case | Stateless apps: web servers, APIs, workers | One copy per node: log shippers, monitoring agents, CNI/kube-proxy, storage daemons | Stateful apps that need identity: databases, Kafka, ZooKeeper, Elasticsearch |
| Pod creation | Through a ReplicaSet, all at once, random name suffix (`cmp-deploy-6685fc4b94-jpbzh`) | One Pod per matching node, random suffix (`cmp-ds-tccbs`) | One at a time in order (0, 1, 2 ...), fixed names (`cmp-sts-0`) |
| Scaling | `replicas`, any order | No `replicas` field: follows the number of (selected) nodes | `replicas`, scales up in order and down in reverse order |
| Networking | Pods are interchangeable behind a ClusterIP Service | Usually reached per node (often hostNetwork/hostPort); can also sit behind a Service | Needs a headless Service; every Pod gets a stable DNS name `pod-N.svc.ns.svc.cluster.local` |
| Storage | Shared or none; a PVC in the template would be shared by all replicas | Usually hostPath (node-local data) | `volumeClaimTemplates`: one PVC per Pod, kept when Pods are rescheduled or scaled down |
| Updates | RollingUpdate / Recreate | RollingUpdate (node by node) / OnDelete | RollingUpdate in reverse ordinal order (optionally partitioned) / OnDelete |
| Examples in this cluster | `coredns`, `metrics-server` | `kube-proxy`, `kindnet` | (none in kube-system; my `cmp-sts`) |

### Scaling

```bash
$ kubectl scale deployment cmp-deploy -n s11-compare --replicas=3
deployment.apps/cmp-deploy scaled
$ kubectl scale rs cmp-rs -n s11-compare --replicas=3
replicaset.apps/cmp-rs scaled
$ kubectl scale statefulset cmp-sts -n s11-compare --replicas=3
statefulset.apps/cmp-sts scaled
$ kubectl scale daemonset cmp-ds -n s11-compare --replicas=3
Error from server (NotFound): the server could not find the requested resource
$ sleep 8; kubectl get deploy,rs,sts,ds -n s11-compare
NAME                         READY   UP-TO-DATE   AVAILABLE   AGE
deployment.apps/cmp-deploy   3/3     3            3           21s

NAME                                    DESIRED   CURRENT   READY   AGE
replicaset.apps/cmp-deploy-6685fc4b94   3         3         3       21s
replicaset.apps/cmp-rs                  3         3         3       21s

NAME                       READY   AGE
statefulset.apps/cmp-sts   3/3     21s

NAME                    DESIRED   CURRENT   READY   UP-TO-DATE   AVAILABLE   NODE SELECTOR   AGE
daemonset.apps/cmp-ds   1         1         1       1            1           <none>          21s
$ kubectl get pods -n s11-compare -l app=cmp-sts
NAME        READY   STATUS    RESTARTS   AGE
cmp-sts-0   1/1     Running   0          21s
cmp-sts-1   1/1     Running   0          20s
cmp-sts-2   1/1     Running   0          8s
$ kubectl get pvc -n s11-compare
NAME             STATUS   VOLUME                                     CAPACITY   ACCESS MODES   STORAGECLASS   VOLUMEATTRIBUTESCLASS   AGE
data-cmp-sts-0   Bound    pvc-6c0af8ef-b48e-4cdb-af6f-8385e45adc43   16Mi       RWO            standard       <unset>                 21s
data-cmp-sts-1   Bound    pvc-d81e1843-7045-4f72-a973-f7433dc9f250   16Mi       RWO            standard       <unset>                 20s
data-cmp-sts-2   Bound    pvc-1ae804c6-71c0-402d-919e-19a52af56537   16Mi       RWO            standard       <unset>                 8s
```

The DaemonSet cannot be scaled at all: it has no `scale` subresource, so the API server returns NotFound. The StatefulSet added the next ordinal `cmp-sts-2` together with a new PVC `data-cmp-sts-2`.

### Storage: StatefulSet PVCs outlive their Pods

```bash
$ kubectl scale statefulset cmp-sts -n s11-compare --replicas=2
statefulset.apps/cmp-sts scaled
$ sleep 5; kubectl get pods,pvc -n s11-compare -l app=cmp-sts
NAME            READY   STATUS    RESTARTS   AGE
pod/cmp-sts-0   1/1     Running   0          50s
pod/cmp-sts-1   1/1     Running   0          49s
...
$ kubectl get pvc -n s11-compare
NAME             STATUS   VOLUME                                     CAPACITY   ACCESS MODES   STORAGECLASS   VOLUMEATTRIBUTESCLASS   AGE
data-cmp-sts-0   Bound    pvc-6c0af8ef-b48e-4cdb-af6f-8385e45adc43   16Mi       RWO            standard       <unset>                 50s
data-cmp-sts-1   Bound    pvc-d81e1843-7045-4f72-a973-f7433dc9f250   16Mi       RWO            standard       <unset>                 49s
data-cmp-sts-2   Bound    pvc-1ae804c6-71c0-402d-919e-19a52af56537   16Mi       RWO            standard       <unset>                 37s
```

Scaling down removed the highest ordinal (`cmp-sts-2`) but kept `data-cmp-sts-2`. If I scale up again, the new `cmp-sts-2` re-attaches to the same data. The PVCs have no owner reference, which is why deleting Pods (or scaling down) does not delete them:

```bash
$ kubectl get pvc -n s11-compare -o custom-columns=PVC:.metadata.name,OWNER:.metadata.ownerReferences[0].kind,VOLUME:.spec.volumeName
PVC              OWNER    VOLUME
data-cmp-sts-0   <none>   pvc-6c0af8ef-b48e-4cdb-af6f-8385e45adc43
data-cmp-sts-1   <none>   pvc-d81e1843-7045-4f72-a973-f7433dc9f250
```

### Networking

The Deployment is reached through one virtual IP; a StatefulSet Pod is reached by its own name (queried here from a client Pod in another namespace, `s11-services`); the DaemonSet Pod knows which node it runs on:

```bash
$ kubectl exec -n s11-services curl-client -- nslookup cmp-deploy-svc.s11-compare.svc.cluster.local
Server:		10.96.0.10
Address:	10.96.0.10:53

Name:	cmp-deploy-svc.s11-compare.svc.cluster.local
Address: 10.106.220.180

$ kubectl exec -n s11-services curl-client -- nslookup cmp-sts-1.cmp-sts.s11-compare.svc.cluster.local
Server:		10.96.0.10
Address:	10.96.0.10:53


Name:	cmp-sts-1.cmp-sts.s11-compare.svc.cluster.local
Address: 10.244.0.241

$ kubectl get pods -n s11-compare -l app=cmp-ds -o wide
NAME           READY   STATUS    RESTARTS   AGE   IP             NODE       NOMINATED NODE   READINESS GATES
cmp-ds-tccbs   1/1     Running   0          61s   10.244.0.235   minikube   <none>           <none>
$ kubectl logs -n s11-compare -l app=cmp-ds --tail=1
agent on node minikube
```

---

## 3. ReplicaSet vs Service

| | ReplicaSet | Service |
| --- | --- | --- |
| Responsibility | **How many** Pods exist: creates replacements when Pods die, scales up/down | **How to reach** the Pods: a stable virtual IP and DNS name, load-balanced over the ready Pods |
| Works with | Pod template + selector | Selector → EndpointSlice of ready Pod IPs |
| Changes over time | Pod names and IPs change whenever Pods are replaced | ClusterIP and DNS name stay the same for the Service's lifetime |
| Implemented by | ReplicaSet controller (kube-controller-manager) | EndpointSlice controller + kube-proxy rules on every node + CoreDNS |

**Why a Service is required:** the ReplicaSet guarantees that 3 Pods exist, but not *which* 3. Every replacement Pod gets a new name and IP, so clients cannot hardcode Pod IPs. The Service gives them one address that follows the Pods automatically.

Here I deleted one Pod of the Deployment and watched what changed:

```bash
$ kubectl get svc cmp-deploy-svc -n s11-compare
NAME             TYPE        CLUSTER-IP       EXTERNAL-IP   PORT(S)   AGE
cmp-deploy-svc   ClusterIP   10.106.220.180   <none>        80/TCP    61s
$ kubectl get pods -n s11-compare -l app=cmp-deploy -o custom-columns=POD:.metadata.name,IP:.status.podIP
POD                           IP
cmp-deploy-568c74d47f-9vrx4   10.244.0.249
cmp-deploy-568c74d47f-dr42w   10.244.0.248
cmp-deploy-568c74d47f-vnxhp   10.244.0.247
$ kubectl get endpointslices -n s11-compare -l kubernetes.io/service-name=cmp-deploy-svc
NAME                   ADDRESSTYPE   PORTS   ENDPOINTS                                AGE
cmp-deploy-svc-xtbnw   IPv4          80      10.244.0.247,10.244.0.248,10.244.0.249   61s
$ kubectl delete pod -n s11-compare $(kubectl get pods -n s11-compare -l app=cmp-deploy -o jsonpath='{.items[0].metadata.name}')
pod "cmp-deploy-568c74d47f-9vrx4" deleted from s11-compare namespace
$ sleep 4; kubectl get pods -n s11-compare -l app=cmp-deploy -o custom-columns=POD:.metadata.name,IP:.status.podIP
POD                           IP
cmp-deploy-568c74d47f-2k4j5   10.244.0.250
cmp-deploy-568c74d47f-dr42w   10.244.0.248
cmp-deploy-568c74d47f-vnxhp   10.244.0.247
$ kubectl get svc cmp-deploy-svc -n s11-compare
NAME             TYPE        CLUSTER-IP       EXTERNAL-IP   PORT(S)   AGE
cmp-deploy-svc   ClusterIP   10.106.220.180   <none>        80/TCP    66s
$ kubectl get endpointslices -n s11-compare -l kubernetes.io/service-name=cmp-deploy-svc
NAME                   ADDRESSTYPE   PORTS   ENDPOINTS                                AGE
cmp-deploy-svc-xtbnw   IPv4          80      10.244.0.247,10.244.0.248,10.244.0.250   67s
$ kubectl exec -n s11-services curl-client -- curl -s -o /dev/null -w 'HTTP %{http_code} from %{remote_ip}\n' http://cmp-deploy-svc.s11-compare
HTTP 200 from 10.106.220.180
```

The ReplicaSet replaced `9vrx4` (10.244.0.249) with `2k4j5` (10.244.0.250). The Service IP `10.106.220.180` did not change. The EndpointSlice swapped `.249` for `.250` on its own, and clients kept using the same name and IP.

### How traffic reaches the Pods

kube-proxy turns the Service and its EndpointSlice into iptables NAT rules on the node. These are the real rules for `cmp-deploy-svc` after the Pod replacement:

```bash
$ minikube ssh -- sudo iptables -t nat -S KUBE-SERVICES | grep cmp-deploy-svc
-A KUBE-SERVICES -d 10.106.220.180/32 -p tcp -m comment --comment "s11-compare/cmp-deploy-svc:http cluster IP" -m tcp --dport 80 -j KUBE-SVC-IRI2HG4H5A4NH5TE
$ CHAIN=$(minikube ssh -- sudo iptables -t nat -S KUBE-SERVICES | grep cmp-deploy-svc | grep -o 'KUBE-SVC-[A-Z0-9]*' | head -1); minikube ssh -- sudo iptables -t nat -S $CHAIN
-N KUBE-SVC-IRI2HG4H5A4NH5TE
-A KUBE-SVC-IRI2HG4H5A4NH5TE ! -s 10.244.0.0/16 -d 10.106.220.180/32 -p tcp -m comment --comment "s11-compare/cmp-deploy-svc:http cluster IP" -m tcp --dport 80 -j KUBE-MARK-MASQ
-A KUBE-SVC-IRI2HG4H5A4NH5TE -m comment --comment "s11-compare/cmp-deploy-svc:http -> 10.244.0.247:80" -m statistic --mode random --probability 0.33333333349 -j KUBE-SEP-46SWD6S7NOD676WL
-A KUBE-SVC-IRI2HG4H5A4NH5TE -m comment --comment "s11-compare/cmp-deploy-svc:http -> 10.244.0.248:80" -m statistic --mode random --probability 0.50000000000 -j KUBE-SEP-W2RLDUEW5MMS4QXS
-A KUBE-SVC-IRI2HG4H5A4NH5TE -m comment --comment "s11-compare/cmp-deploy-svc:http -> 10.244.0.250:80" -j KUBE-SEP-WH3SY43FBBKRU4YP
$ minikube ssh -- sudo iptables -t nat -S | grep 'KUBE-SEP' | grep 'cmp-deploy-svc' | grep DNAT
-A KUBE-SEP-46SWD6S7NOD676WL -p tcp -m comment --comment "s11-compare/cmp-deploy-svc:http" -m tcp -j DNAT --to-destination 10.244.0.247:80
-A KUBE-SEP-W2RLDUEW5MMS4QXS -p tcp -m comment --comment "s11-compare/cmp-deploy-svc:http" -m tcp -j DNAT --to-destination 10.244.0.248:80
-A KUBE-SEP-WH3SY43FBBKRU4YP -p tcp -m comment --comment "s11-compare/cmp-deploy-svc:http" -m tcp -j DNAT --to-destination 10.244.0.250:80
```

The path of a request:

1. The client resolves `cmp-deploy-svc.s11-compare` through CoreDNS and gets the ClusterIP `10.106.220.180`.
2. The packet to `10.106.220.180:80` matches the `KUBE-SERVICES` rule and jumps to the Service chain `KUBE-SVC-...`.
3. That chain picks one endpoint at random: 1/3 for the first, then 1/2 of the rest, then the last one, which is an even 1/3 each.
4. The chosen `KUBE-SEP-...` rule DNATs the packet to the Pod IP and port (e.g. `10.244.0.250:80`), and the CNI network delivers it to the Pod.

The ReplicaSet never appears in this path. It only makes sure there are Pods, and the Service rules point at whichever Pods are currently ready.
