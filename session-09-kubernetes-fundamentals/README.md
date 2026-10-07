# Session 09: Kubernetes Fundamentals

**Name:** Vansh Srivastava
**Enrollment No.:** 24bcs10567
**Session:** 09

This session is my first hands-on with Kubernetes. I set up a local single-node cluster with Minikube, checked that it is healthy, looked at every control plane and node component running inside `kube-system`, practised the basic objects and `kubectl` commands, and then worked through all six modules of the official Kubernetes Basics tutorial (deploy, explore, expose, scale, rolling update and rollback).

## Folder structure

```text
session-09-kubernetes-fundamentals/
├── README.md                 # this file: commands, real output, notes
├── .gitignore
└── manifests/
    ├── namespace.yaml        # s09-basics namespace used in Task 4
    └── hello-pod.yaml        # a hand-written Pod for the declarative workflow (Task 4)
```

## Environment

```text
Host:        macOS 26 on Apple Silicon (arm64), Docker from Colima (Docker Engine 29.5.2)
Minikube:    v1.39.0, docker driver, single node "minikube"
Kubernetes:  v1.37.0 (server), kubectl v1.37.1 (client), containerd 2.3.4 runtime
Node:        Debian 12 (bookworm), arm64, 6 CPU / ~9.7 GiB visible to the node
```

All commands below were run from my Mac terminal. I used my own namespaces (`s09-basics`, `s09-bootcamp`) and deleted them at the end.

---

## Task 1: Install and configure Minikube

Minikube and kubectl are already installed on this Mac. Both binaries are in the Homebrew prefix:

```bash
$ which minikube kubectl
/opt/homebrew/bin/minikube
/opt/homebrew/bin/kubectl
$ kubectl version --client
Client Version: v1.37.1
Kustomize Version: v5.8.1
```

(For reference, a fresh install on an Apple Silicon Mac is `brew install minikube kubectl`. I did not re-run it because the tools were already there.)

The cluster was created with the Docker driver (Docker comes from Colima). This is the real log of the first `minikube start` on this machine. I only removed the hundreds of download progress-bar updates and kept the final 100% line:

```bash
$ minikube version
minikube version: v1.39.0
commit: 7a9f6a841470a207de8cf4bafcccee0969d8ba10

$ minikube start --driver=docker --cpus=4 --memory=6g --kubernetes-version=stable
* minikube v1.39.0 on Darwin 26.6.2 (arm64)
* Using the docker driver based on user configuration
* Using Docker Desktop driver with root privileges
* Starting "minikube" primary control-plane node in "minikube" cluster
* Pulling base image v0.0.51 ...
* Downloading Kubernetes v1.37.0 preload ...
    > gcr.io/k8s-minikube/kicbase:  470.53 MiB / 470.53 MiB  100.00% 10.43 MiB
* Preparing Kubernetes v1.37.0 on containerd 2.3.4 ...
* Configuring CNI (Container Networking Interface) ...
* Verifying Kubernetes components...
  - Using image gcr.io/k8s-minikube/storage-provisioner:v5
* Enabled addons: storage-provisioner, default-storageclass
* Done! kubectl is now configured to use "minikube" cluster and "default" namespace by default
```

What the flags mean:

- `--driver=docker`: the Kubernetes "node" is a Docker container (kicbase image) running inside Colima's Linux VM. No separate VM is needed.
- `--cpus=4 --memory=6g`: resource limits for the node container. (`kubectl describe node` in Task 3 still reports 6 CPU and ~9.7 GiB, which is the size of the Colima VM: with the docker driver the limits are applied to the container, while the kubelet reads the VM's totals.)
- `--kubernetes-version=stable`: picked the latest stable release, which resolved to **v1.37.0**.
- minikube chose **containerd** as the container runtime inside the node and set up a CNI plugin (kindnet).

Configuration that `minikube start` wrote:

```bash
$ minikube profile list
┌──────────┬────────┬────────────┬──────────────┬─────────┬────────┬───────┬────────────────┬────────────────────┐
│ PROFILE  │ DRIVER │  RUNTIME   │      IP      │ VERSION │ STATUS │ NODES │ ACTIVE PROFILE │ ACTIVE KUBECONTEXT │
├──────────┼────────┼────────────┼──────────────┼─────────┼────────┼───────┼────────────────┼────────────────────┤
│ minikube │ docker │ containerd │ 192.168.49.2 │ v1.37.0 │ OK     │ 1     │ *              │ *                  │
└──────────┴────────┴────────────┴──────────────┴─────────┴────────┴───────┴────────────────┴────────────────────┘
$ kubectl config current-context
minikube
$ kubectl config get-contexts
CURRENT   NAME       CLUSTER    AUTHINFO   NAMESPACE
*         minikube   minikube   minikube   default
```

Add-ons that are switched on in this cluster (I listed them as JSON to keep the output short):

```bash
$ minikube addons list -o json | jq -r 'to_entries[] | select(.value.Status=="enabled") | .key'
default-storageclass
ingress
metrics-server
storage-provisioner
```

`minikube start` also points kubectl at the new cluster: the `minikube` context is the current one, and its server URL (`https://127.0.0.1:32771`, see Task 2) is a port that Docker publishes from the node container to the Mac.

## Task 2: Verify cluster status

```bash
$ minikube status
minikube
type: Control Plane
host: Running
kubelet: Running
apiserver: Running
kubeconfig: Configured
$ kubectl cluster-info
Kubernetes control plane is running at https://127.0.0.1:32771
CoreDNS is running at https://127.0.0.1:32771/api/v1/namespaces/kube-system/services/kube-dns:dns/proxy

To further debug and diagnose cluster problems, use 'kubectl cluster-info dump'.
$ kubectl get nodes -o wide
NAME       STATUS   ROLES           AGE     VERSION   INTERNAL-IP    EXTERNAL-IP   OS-IMAGE                         KERNEL-VERSION              CONTAINER-RUNTIME
minikube   Ready    control-plane   9m27s   v1.37.0   192.168.49.2   <none>        Debian GNU/Linux 12 (bookworm)   6.8.0-117-generic (arm64)   containerd://2.3.4
```

The node is `Ready`, runs Kubernetes v1.37.0 on arm64 and uses containerd. Its InternalIP `192.168.49.2` lives on the Docker network inside Colima, so it is not reachable directly from macOS (this matters later for NodePort tests).

Health checks of the API server and of the core components:

```bash
$ kubectl get --raw='/readyz?verbose' | head -8
[+]ping ok
[+]log ok
[+]etcd ok
[+]etcd-readiness ok
[+]informer-sync ok
[+]poststarthook/start-apiserver-admission-initializer ok
[+]poststarthook/generic-apiserver-start-informers ok
[+]poststarthook/priority-and-fairness-config-consumer ok
```

```bash
$ kubectl get --raw='/readyz?verbose' | tail -25
...
[+]poststarthook/kube-apiserver-autoregistration ok
[+]autoregister-completion ok
[+]poststarthook/apiservice-openapi-controller ok
[+]poststarthook/apiservice-openapiv3-controller ok
[+]shutdown ok
readyz check passed
```

```bash
$ kubectl get componentstatuses
Warning: v1 ComponentStatus is deprecated in v1.19+
NAME                 STATUS    MESSAGE   ERROR
scheduler            Healthy   ok        
controller-manager   Healthy   ok        
etcd-0               Healthy   ok        
```

`readyz` reports every check as `ok` (including `etcd`), and `componentstatuses` (deprecated, but still handy) says the scheduler, controller-manager and etcd are healthy.

The four namespaces every cluster starts with:

```bash
$ kubectl get ns default kube-system kube-public kube-node-lease
NAME              STATUS   AGE
default           Active   9m36s
kube-system       Active   9m36s
kube-public       Active   9m36s
kube-node-lease   Active   9m36s
```

## Task 3: Explore Kubernetes architecture

### Notes: how a cluster is built

```text
                         CONTROL PLANE (node "minikube")
   kubectl ──HTTPS──►  kube-apiserver  ◄──────►  etcd (key-value store, the cluster's database)
                          ▲    ▲    ▲
          watches/updates │    │    │ watches/updates
          kube-scheduler ─┘    │    └─ kube-controller-manager (Deployment, ReplicaSet, Node, Job ... controllers)
                               │
                         WORKER SIDE (same node here)
                    kubelet ───┘  ── CRI ──► containerd ──► Pod containers
                    kube-proxy (programs iptables for Services)
                    CNI plugin (kindnet) gives each Pod an IP
                    Add-ons: CoreDNS, metrics-server, storage-provisioner, ingress-nginx
```

**Control plane components**

| Component | What it does | Where I see it here |
| --- | --- | --- |
| kube-apiserver | Front door of the cluster. Every `kubectl` call and every component talks to it over HTTPS; it validates objects and stores them in etcd. | static Pod `kube-apiserver-minikube` |
| etcd | Consistent key-value store that holds the whole cluster state (all objects). | static Pod `etcd-minikube`, listening on `127.0.0.1:2379` |
| kube-scheduler | Picks a node for every new Pod that has no node yet (looks at resources, taints, affinity). | static Pod `kube-scheduler-minikube` |
| kube-controller-manager | Runs the control loops (Deployment, ReplicaSet, Node, Endpoint/EndpointSlice, Job, ...) that keep the actual state equal to the desired state. | static Pod `kube-controller-manager-minikube` |
| cloud-controller-manager | Talks to a cloud provider (load balancers, node lifecycle). | not present: Minikube is not a cloud |

**Node components**

| Component | What it does | Where I see it here |
| --- | --- | --- |
| kubelet | Agent on each node. Watches the API for Pods assigned to its node, starts them through the container runtime, runs probes, reports status. | systemd service inside the node (not a Pod) |
| container runtime | Pulls images and runs containers (via CRI). | containerd 2.3.4, systemd service |
| kube-proxy | Turns Services into iptables rules on the node so a ClusterIP reaches Pod IPs. | DaemonSet `kube-proxy` |
| CNI plugin | Gives Pods an IP and connects them to the Pod network. | DaemonSet `kindnet` |

### Seeing the components in `kube-system`

```bash
$ kubectl get pods -n kube-system -o wide
NAME                               READY   STATUS    RESTARTS   AGE     IP             NODE       NOMINATED NODE   READINESS GATES
coredns-559f6c778d-mb9q4           1/1     Running   0          9m27s   10.244.0.2     minikube   <none>           <none>
etcd-minikube                      1/1     Running   0          9m34s   192.168.49.2   minikube   <none>           <none>
kindnet-vtqnp                      1/1     Running   0          9m27s   192.168.49.2   minikube   <none>           <none>
kube-apiserver-minikube            1/1     Running   0          9m34s   192.168.49.2   minikube   <none>           <none>
kube-controller-manager-minikube   1/1     Running   0          9m34s   192.168.49.2   minikube   <none>           <none>
kube-proxy-b8g6s                   1/1     Running   0          9m27s   192.168.49.2   minikube   <none>           <none>
kube-scheduler-minikube            1/1     Running   0          9m34s   192.168.49.2   minikube   <none>           <none>
metrics-server-768f9f6999-d4rzf    1/1     Running   0          8m18s   10.244.0.6     minikube   <none>           <none>
storage-provisioner                1/1     Running   0          9m33s   192.168.49.2   minikube   <none>           <none>
$ kubectl get pods -n kube-system -l tier=control-plane -L component
NAME                               READY   STATUS    RESTARTS   AGE     COMPONENT
etcd-minikube                      1/1     Running   0          9m34s   etcd
kube-apiserver-minikube            1/1     Running   0          9m34s   kube-apiserver
kube-controller-manager-minikube   1/1     Running   0          9m34s   kube-controller-manager
kube-scheduler-minikube            1/1     Running   0          9m34s   kube-scheduler
```

The four control plane Pods and kube-proxy/kindnet show the node IP `192.168.49.2` because they run with `hostNetwork: true`. CoreDNS and metrics-server are normal Pods, so they get Pod IPs from `10.244.0.0/24`.

The control plane Pods are **static Pods**: the kubelet starts them straight from files on the node, which is why their names end in `-minikube` (the node name):

```bash
$ minikube ssh -- sudo ls -l /etc/kubernetes/manifests
total 20
-rw------- 1 root root 2655 Oct  7 17:36 etcd.yaml
-rw------- 1 root root 4171 Oct  7 17:36 kube-apiserver.yaml
-rw------- 1 root root 3254 Oct  7 17:36 kube-controller-manager.yaml
-rw------- 1 root root 1727 Oct  7 17:36 kube-scheduler.yaml
```

The kubelet and containerd are not Pods at all. They are systemd services on the node, and `crictl` (the CRI client) shows the containers containerd is running for the system components:

```bash
$ minikube ssh -- systemctl is-active kubelet containerd
active
active
$ minikube ssh -- 'sudo crictl ps --name "kube-|etcd|coredns" -o table' | cut -c1-140
CONTAINER           IMAGE               CREATED             STATE               NAME                      ATTEMPT             POD ID        
afb08d104cc33       fbccbf70a429f       9 minutes ago       Running             coredns                   0                   7233a76e21f05 
3c68e62580397       550b682d81d41       9 minutes ago       Running             kube-proxy                0                   47c1d1a0f92e8 
2a115334500ae       b1ad0e33c9012       9 minutes ago       Running             kube-controller-manager   0                   ea0b8882abda7 
ce114d4ca145d       384eabc4fe526       9 minutes ago       Running             kube-scheduler            0                   6826194df9ca7 
f4408fae0518d       c2e426bbd1cd6       9 minutes ago       Running             etcd                      0                   e6c3792a5815b 
2326adc921521       6003d52023b9d       9 minutes ago       Running             kube-apiserver            0                   9e57fe9ce0ed9 
```

Add-ons are ordinary Kubernetes workloads:

```bash
$ kubectl get daemonset -n kube-system
NAME         DESIRED   CURRENT   READY   UP-TO-DATE   AVAILABLE   NODE SELECTOR            AGE
kindnet      1         1         1       1            1           <none>                   9m33s
kube-proxy   1         1         1       1            1           kubernetes.io/os=linux   9m34s
$ kubectl get deployment -n kube-system
NAME             READY   UP-TO-DATE   AVAILABLE   AGE
coredns          1/1     1            1           9m34s
metrics-server   1/1     1            1           8m18s
```

A few API server and controller-manager flags show how the pieces are wired together (etcd address, RBAC, the Service IP range and the Pod IP range):

```bash
$ kubectl get pod -n kube-system kube-apiserver-minikube -o jsonpath='{range .spec.containers[0].command[*]}{@}{"\n"}{end}' | grep -E 'kube-apiserver$|etcd-servers|authorization-mode|service-cluster-ip-range|secure-port|advertise-address'
kube-apiserver
--advertise-address=192.168.49.2
--authorization-mode=Node,RBAC
--etcd-servers=https://127.0.0.1:2379
--secure-port=8443
--service-cluster-ip-range=10.96.0.0/12
$ kubectl get pod -n kube-system kube-controller-manager-minikube -o jsonpath='{range .spec.containers[0].command[*]}{@}{"\n"}{end}' | grep -E 'controller-manager$|controllers|cluster-cidr|leader-elect'
kube-controller-manager
--cluster-cidr=10.244.0.0/16
--controllers=*,bootstrapsigner,tokencleaner
--leader-elect=false
```

Node capacity and what the kubelet reports about the machine:

```bash
$ kubectl describe node minikube | sed -n '/^Capacity/,/^System Info/p'
Capacity:
  cpu:                6
  ephemeral-storage:  63088406528
  hugepages-1Gi:      0
  hugepages-2Mi:      0
  hugepages-32Mi:     0
  hugepages-64Ki:     0
  memory:             10159960Ki
  pods:               110
...
```

```bash
$ kubectl describe node minikube | sed -n '/^System Info/,/^Non-terminated/p'
System Info:
  Machine ID:                 c7552358bf1aab9f1f21b3de6a971616
  System UUID:                515d1c3f-b0e3-499e-b3b2-67a7fb94724d
  Boot ID:                    4a59c6dd-58b3-4c6e-8486-fc57556add43
  Kernel Version:             6.8.0-117-generic
  OS Image:                   Debian GNU/Linux 12 (bookworm)
  Operating System:           linux
  Architecture:               arm64
  Container Runtime Version:  containerd://2.3.4
  Kubelet Version:            v1.37.0
PodCIDR:                      10.244.0.0/24
PodCIDRs:                     10.244.0.0/24
Non-terminated Pods:          (17 in total)
```

```bash
$ kubectl describe node minikube | sed -n '/^Allocated resources/,/^Events/p'
Allocated resources:
  (Total limits may be over 100 percent, i.e., overcommitted.)
  Resource           Requests     Limits
  --------           --------     ------
  cpu                1050m (17%)  100m (1%)
  memory             510Mi (5%)   220Mi (2%)
  ephemeral-storage  0 (0%)       0 (0%)
  hugepages-1Gi      0 (0%)       0 (0%)
  hugepages-2Mi      0 (0%)       0 (0%)
  hugepages-32Mi     0 (0%)       0 (0%)
  hugepages-64Ki     0 (0%)       0 (0%)
Events:
```

What I took from this: the "cluster" is one Docker container that plays both roles. It is arm64, Pods get IPs from `10.244.0.0/24`, Services get virtual IPs from `10.96.0.0/12`, and the node can run up to 110 Pods.

## Task 4: Basic Kubernetes objects and commands

### Objects I used in this course so far

| Object | Purpose |
| --- | --- |
| Pod | Smallest deployable unit: one or more containers that share an IP and volumes. |
| ReplicaSet | Keeps N identical Pods running (replaces Pods that die). |
| Deployment | Manages ReplicaSets; adds rolling updates, rollback and history. |
| Service | Stable virtual IP + DNS name in front of a changing set of Pods. |
| Namespace | Logical partition of the cluster for names, quotas and access control. |
| ConfigMap / Secret | Configuration and sensitive values injected into Pods. |
| DaemonSet / StatefulSet / Job | One Pod per node / Pods with stable identity and storage / run-to-completion work. |

### Commands I practised

| Command | What it does |
| --- | --- |
| `kubectl api-resources` | Lists every object type the API server knows, with short names. |
| `kubectl explain <type.field>` | Built-in documentation for any field. |
| `kubectl run` / `kubectl create` | Imperative creation. |
| `kubectl apply -f file.yaml` | Declarative creation/update from YAML. |
| `kubectl get` (`-o wide`, `--show-labels`, `-l`) | List objects. |
| `kubectl describe` | Full details plus the Events at the bottom. |
| `kubectl logs` / `kubectl exec` | Container output / run a command inside a container. |
| `kubectl delete` | Remove objects. |

```bash
$ kubectl api-resources | grep -E '^(NAME|pods|services|namespaces|nodes|configmaps|secrets|deployments|replicasets|daemonsets|statefulsets|jobs|cronjobs|endpointslices) '
NAME                                SHORTNAMES         APIVERSION                        NAMESPACED   KIND
configmaps                          cm                 v1                                true         ConfigMap
namespaces                          ns                 v1                                false        Namespace
nodes                               no                 v1                                false        Node
pods                                po                 v1                                true         Pod
secrets                                                v1                                true         Secret
services                            svc                v1                                true         Service
daemonsets                          ds                 apps/v1                           true         DaemonSet
deployments                         deploy             apps/v1                           true         Deployment
replicasets                         rs                 apps/v1                           true         ReplicaSet
statefulsets                        sts                apps/v1                           true         StatefulSet
cronjobs                            cj                 batch/v1                          true         CronJob
jobs                                                   batch/v1                          true         Job
endpointslices                                         discovery.k8s.io/v1               true         EndpointSlice
nodes                                                  metrics.k8s.io/v1beta1            false        NodeMetrics
pods                                                   metrics.k8s.io/v1beta1            true         PodMetrics
```

```bash
$ kubectl explain pod.spec.containers.image
KIND:       Pod
VERSION:    v1

FIELD: image <string>


DESCRIPTION:
    Container image name. More info:
    https://kubernetes.io/docs/concepts/containers/images This field is optional
    to allow higher level config management to default or override container
    images in workload controllers like Deployments and StatefulSets.
```

Creating one Pod imperatively and one declaratively from [manifests/hello-pod.yaml](manifests/hello-pod.yaml):

```bash
$ kubectl apply -f manifests/namespace.yaml
namespace/s09-basics created
$ kubectl run nginx-imperative --image=public.ecr.aws/docker/library/nginx:1.27-alpine --port=80 -n s09-basics
pod/nginx-imperative created
$ kubectl apply -f manifests/hello-pod.yaml
pod/hello-pod created
$ kubectl wait --for=condition=Ready pod --all -n s09-basics --timeout=120s
pod/hello-pod condition met
pod/nginx-imperative condition met
$ kubectl get pods -n s09-basics -o wide --show-labels
NAME               READY   STATUS    RESTARTS   AGE   IP            NODE       NOMINATED NODE   READINESS GATES   LABELS
hello-pod          1/1     Running   0          20s   10.244.0.15   minikube   <none>           <none>            app=hello,session=09
nginx-imperative   1/1     Running   0          20s   10.244.0.14   minikube   <none>           <none>            run=nginx-imperative
$ kubectl get pods -n s09-basics -l app=hello
NAME        READY   STATUS    RESTARTS   AGE
hello-pod   1/1     Running   0          20s
```

`kubectl run` added the label `run=nginx-imperative` by itself, while `hello-pod` has the labels I wrote in YAML, so the `-l app=hello` selector only returns that one Pod.

Inspecting the Pod (events, a request from inside the container, the logs, and single fields with JSONPath):

```bash
$ kubectl describe pod hello-pod -n s09-basics | sed -n '/^Events:/,$p'
Events:
  Type    Reason     Age   From               Message
  ----    ------     ----  ----               -------
  Normal  Scheduled  25s   default-scheduler  Successfully assigned s09-basics/hello-pod to minikube
  Normal  Pulling    24s   kubelet            spec.containers{web}: Pulling image "public.ecr.aws/docker/library/nginx:1.27-alpine"
  Normal  Pulled     5s    kubelet            spec.containers{web}: Successfully pulled image "public.ecr.aws/docker/library/nginx:1.27-alpine" in 2.235s (18.962s including waiting). Image size: 21832241 bytes.
  Normal  Created    5s    kubelet            spec.containers{web}: Container created
  Normal  Started    5s    kubelet            spec.containers{web}: Container started
$ kubectl exec -n s09-basics hello-pod -- wget -qO- http://localhost:80 | head -4
<!DOCTYPE html>
<html>
<head>
<title>Welcome to nginx!</title>
$ kubectl logs -n s09-basics hello-pod --tail=3
2026/10/07 17:46:51 [notice] 1#1: start worker process 34
2026/10/07 17:46:51 [notice] 1#1: start worker process 35
::1 - - [07/Oct/2026:17:46:56 +0000] "GET / HTTP/1.1" 200 615 "-" "Wget" "-"
$ kubectl get pod hello-pod -n s09-basics -o jsonpath='{.status.phase} {.status.podIP} {.spec.nodeName}{"\n"}'
Running 10.244.0.15 minikube
```

The Events show the full start sequence: scheduled to `minikube`, image pulled, container created, started. The access-log line from `::1` in the logs is my own `wget` from inside the container.

Deleting a bare Pod removes it for good. Nothing recreates it, because no controller owns it:

```bash
$ kubectl delete pod nginx-imperative -n s09-basics
pod "nginx-imperative" deleted from s09-basics namespace
$ kubectl get pods -n s09-basics
NAME        READY   STATUS    RESTARTS   AGE
hello-pod   1/1     Running   0          27s
```

## Task 5: Kubernetes Basics tutorial (hands-on)

I followed the six modules of <https://kubernetes.io/docs/tutorials/kubernetes-basics/> in namespace `s09-bootcamp`. Module 1 ("create a cluster") is Task 1 and Task 2 above.

### arm64 note about the tutorial image

The tutorial image `gcr.io/google-samples/kubernetes-bootcamp:v1` is an old, amd64-only image (a single manifest, not a multi-arch list):

```bash
$ docker buildx imagetools inspect gcr.io/google-samples/kubernetes-bootcamp:v1 | head -3
Name:      gcr.io/google-samples/kubernetes-bootcamp:v1
MediaType: application/vnd.docker.distribution.manifest.v2+json
Digest:    sha256:0d6b8ee63bb57c5f5b6156f446b3bc3b3c143d233037f3a2f00e279c8fcc64af
$ docker buildx imagetools inspect gcr.io/google-samples/kubernetes-bootcamp:v1 --format '{{json .Image}}' | jq -r '.os + "/" + .architecture'
linux/amd64
```

I tried it anyway and it **did run**. The reason is that the Linux VM under Colima has QEMU user-mode emulation registered with the kernel (`binfmt_misc`), so x86_64 binaries are run through `qemu-x86_64` transparently. Inside the container `uname -m` reports `x86_64`, while the node itself is `aarch64`:

```bash
$ kubectl exec -n s09-bootcamp deploy/kubernetes-bootcamp -- uname -m
x86_64
$ minikube ssh -- uname -m
aarch64
$ minikube ssh -- ls /proc/sys/fs/binfmt_misc/
python3.12  qemu-i386  qemu-x86_64  register  status
```

```bash
$ minikube ssh -- cat /proc/sys/fs/binfmt_misc/qemu-x86_64 | head -3
enabled
interpreter /usr/bin/qemu-x86_64
flags: POCF
```

So I kept the real tutorial image. Without that emulation the container would have exited with `exec format error` and I would have needed an arm64 build.

### Module 2: Deploy an app

```bash
$ kubectl create namespace s09-bootcamp
namespace/s09-bootcamp created
$ kubectl create deployment kubernetes-bootcamp --image=gcr.io/google-samples/kubernetes-bootcamp:v1 -n s09-bootcamp
deployment.apps/kubernetes-bootcamp created
```

```bash
$ kubectl get deployments -n s09-bootcamp
NAME                  READY   UP-TO-DATE   AVAILABLE   AGE
kubernetes-bootcamp   1/1     1            1           86s
```

The tutorial uses `kubectl proxy` to reach the API from the terminal. I ran it in the background on port 18101:

```bash
$ kubectl proxy --port=18101 &
Starting to serve on 127.0.0.1:18101
```

```bash
$ curl -s http://localhost:18101/version
{
  "major": "1",
  "minor": "37",
  "emulationMajor": "1",
  "emulationMinor": "37",
  "minCompatibilityMajor": "1",
  "minCompatibilityMinor": "36",
  "gitVersion": "v1.37.0",
  "gitCommit": "f54c212e3a2f75d674b717a9b29052b20b60aefc",
  "gitTreeState": "clean",
  "buildDate": "2026-08-26T10:44:25Z",
  "goVersion": "go1.26.6",
  "compiler": "gc",
  "platform": "linux/arm64"
}
$ export POD_NAME=$(kubectl get pods -n s09-bootcamp -o go-template --template '{{range .items}}{{.metadata.name}}{{"\n"}}{{end}}'); echo Name of the Pod: $POD_NAME
Name of the Pod: kubernetes-bootcamp-5cc66bcc9b-7rm97
```

### Module 3: Explore the app (Pods, logs, exec)

```bash
$ kubectl get pods -n s09-bootcamp
NAME                                   READY   STATUS    RESTARTS   AGE
kubernetes-bootcamp-5cc66bcc9b-7rm97   1/1     Running   0          95s
$ kubectl describe pods -n s09-bootcamp | sed -n '1,12p;/^Containers:/,/^Conditions:/p'
Name:             kubernetes-bootcamp-5cc66bcc9b-7rm97
Namespace:        s09-bootcamp
Priority:         0
Service Account:  default
Node:             minikube/192.168.49.2
Start Time:       Wed, 07 Oct 2026 23:17:02 +0530
Labels:           app=kubernetes-bootcamp
                  pod-template-hash=5cc66bcc9b
Annotations:      <none>
Status:           Running
IP:               10.244.0.16
IPs:
Containers:
  kubernetes-bootcamp:
    Container ID:   containerd://f1b824e38b82fc22f5a8ddf5359f0637a4787ce169b3971a486c8aed9f8e61fa
    Image:          gcr.io/google-samples/kubernetes-bootcamp:v1
    Image ID:       gcr.io/google-samples/kubernetes-bootcamp@sha256:0d6b8ee63bb57c5f5b6156f446b3bc3b3c143d233037f3a2f00e279c8fcc64af
    Port:           <none>
    Host Port:      <none>
    State:          Running
      Started:      Wed, 07 Oct 2026 23:17:41 +0530
    Ready:          True
    Restart Count:  0
    Environment:    <none>
    Mounts:
      /var/run/secrets/kubernetes.io/serviceaccount from kube-api-access-zm67k (ro)
Conditions:
```

The Pod got IP `10.244.0.16`, has the labels `app=kubernetes-bootcamp` and `pod-template-hash=5cc66bcc9b` (added by the Deployment's ReplicaSet), and runs the v1 image. Reaching the app through the API server proxy:

```bash
$ curl -s http://localhost:18101/api/v1/namespaces/s09-bootcamp/pods/$POD_NAME:8080/proxy/
Hello Kubernetes bootcamp! | Running on: kubernetes-bootcamp-5cc66bcc9b-7rm97 | v=1
```

Logs, environment and a shell inside the container:

```bash
$ kubectl logs -n s09-bootcamp $POD_NAME
Kubernetes Bootcamp App Started At: 2026-10-07T17:47:42.363Z | Running On:  kubernetes-bootcamp-5cc66bcc9b-7rm97 

Running On: kubernetes-bootcamp-5cc66bcc9b-7rm97 | Total Requests: 1 | App Uptime: 11.282 seconds | Log Time: 2026-10-07T17:47:53.646Z
Running On: kubernetes-bootcamp-5cc66bcc9b-7rm97 | Total Requests: 2 | App Uptime: 54.812 seconds | Log Time: 2026-10-07T17:48:37.175Z
$ kubectl exec -n s09-bootcamp $POD_NAME -- env
HOME=/root
KUBERNETES_SERVICE_HOST=10.96.0.1
KUBERNETES_PORT_443_TCP_ADDR=10.96.0.1
KUBERNETES_PORT_443_TCP_PORT=443
KUBERNETES_PORT_443_TCP_PROTO=tcp
KUBERNETES_PORT_443_TCP=tcp://10.96.0.1:443
KUBERNETES_PORT=tcp://10.96.0.1:443
KUBERNETES_SERVICE_PORT_HTTPS=443
KUBERNETES_SERVICE_PORT=443
NODE_VERSION=6.3.1
NPM_CONFIG_LOGLEVEL=info
HOSTNAME=kubernetes-bootcamp-5cc66bcc9b-7rm97
PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
$ kubectl exec -n s09-bootcamp $POD_NAME -- cat server.js
var http = require('http');
var requests=0;
var podname= process.env.HOSTNAME;
var startTime;
var host;
var handleRequest = function(request, response) {
  response.setHeader('Content-Type', 'text/plain');
  response.writeHead(200);
  response.write("Hello Kubernetes bootcamp! | Running on: ");
  response.write(host);
  response.end(" | v=1\n");
  console.log("Running On:" ,host, "| Total Requests:", ++requests,"| App Uptime:", (new Date() - startTime)/1000 , "seconds", "| Log Time:",new Date());
}
var www = http.createServer(handleRequest);
www.listen(8080,function () {
    startTime = new Date();;
    host = process.env.HOSTNAME;
    console.log ("Kubernetes Bootcamp App Started At:",startTime, "| Running On: " ,host, "\n" );
});
$ kubectl exec -n s09-bootcamp $POD_NAME -- curl -s http://localhost:8080
Hello Kubernetes bootcamp! | Running on: kubernetes-bootcamp-5cc66bcc9b-7rm97 | v=1
```

The log shows my two requests so far (one through the proxy, one from `curl`). The environment already contains `KUBERNETES_SERVICE_HOST=10.96.0.1`: Kubernetes injects variables for Services that existed when the Pod started. `server.js` is the whole app: it answers with the Pod name and `v=1`.

### Module 4: Expose the app with a Service

```bash
$ kubectl get services -n s09-bootcamp
No resources found in s09-bootcamp namespace.
$ kubectl expose deployment/kubernetes-bootcamp --type=NodePort --port 8080 -n s09-bootcamp
service/kubernetes-bootcamp exposed
$ kubectl get services -n s09-bootcamp
NAME                  TYPE       CLUSTER-IP      EXTERNAL-IP   PORT(S)          AGE
kubernetes-bootcamp   NodePort   10.102.218.63   <none>        8080:31621/TCP   0s
$ kubectl describe services/kubernetes-bootcamp -n s09-bootcamp
Name:                     kubernetes-bootcamp
Namespace:                s09-bootcamp
Labels:                   app=kubernetes-bootcamp
Annotations:              <none>
Selector:                 app=kubernetes-bootcamp
Type:                     NodePort
IP Family Policy:         SingleStack
IP Families:              IPv4
IP:                       10.102.218.63
IPs:                      10.102.218.63
Port:                     <unset>  8080/TCP
TargetPort:               8080/TCP
NodePort:                 <unset>  31621/TCP
Endpoints:                10.244.0.16:8080
Session Affinity:         None
External Traffic Policy:  Cluster
Internal Traffic Policy:  Cluster
Events:                   <none>
$ export NODE_PORT=$(kubectl get services/kubernetes-bootcamp -n s09-bootcamp -o go-template='{{(index .spec.ports 0).nodePort}}'); echo NODE_PORT=$NODE_PORT
NODE_PORT=31621
```

The Service got a ClusterIP (`10.102.218.63`) and a NodePort (`31621`), and its single endpoint is the Pod IP from Module 3.

With the docker driver on macOS the node IP is not routable from the Mac, so the tutorial's `curl $(minikube ip):$NODE_PORT` times out (curl exit code 28). The NodePort works from inside the node, and from the Mac I used a port-forward on my assigned port 18102:

```bash
$ curl -s --max-time 5 http://$(minikube ip):$NODE_PORT; echo "exit code: $?"
exit code: 28
$ minikube ssh -- curl -s http://localhost:$NODE_PORT
Hello Kubernetes bootcamp! | Running on: kubernetes-bootcamp-5cc66bcc9b-7rm97 | v=1
$ kubectl port-forward -n s09-bootcamp svc/kubernetes-bootcamp 18102:8080 &
Forwarding from 127.0.0.1:18102 -> 8080
Forwarding from [::1]:18102 -> 8080
$ curl -s http://localhost:18102
Hello Kubernetes bootcamp! | Running on: kubernetes-bootcamp-5cc66bcc9b-7rm97 | v=1
```

Labels: the Deployment created the label `app=kubernetes-bootcamp`; I added `version=v1` to the Pod and used both as selectors:

```bash
$ kubectl describe deployment kubernetes-bootcamp -n s09-bootcamp | grep -E '^(Labels|Selector)'
Labels:                 app=kubernetes-bootcamp
Selector:               app=kubernetes-bootcamp
$ kubectl get pods -l app=kubernetes-bootcamp -n s09-bootcamp
NAME                                   READY   STATUS    RESTARTS   AGE
kubernetes-bootcamp-5cc66bcc9b-7rm97   1/1     Running   0          2m8s
$ kubectl get services -l app=kubernetes-bootcamp -n s09-bootcamp
NAME                  TYPE       CLUSTER-IP      EXTERNAL-IP   PORT(S)          AGE
kubernetes-bootcamp   NodePort   10.102.218.63   <none>        8080:31621/TCP   22s
$ kubectl label pods $POD_NAME version=v1 -n s09-bootcamp
pod/kubernetes-bootcamp-5cc66bcc9b-7rm97 labeled
$ kubectl describe pods $POD_NAME -n s09-bootcamp | sed -n '/^Labels:/,/^Annotations:/p'
Labels:           app=kubernetes-bootcamp
                  pod-template-hash=5cc66bcc9b
                  version=v1
Annotations:      <none>
$ kubectl get pods -l version=v1 -n s09-bootcamp
NAME                                   READY   STATUS    RESTARTS   AGE
kubernetes-bootcamp-5cc66bcc9b-7rm97   1/1     Running   0          2m8s
```

Deleting the Service by label. The NodePort stops answering (curl exit code 7 inside the node, "connection refused"), but the app itself keeps running, which proves the Service was only the entry point:

```bash
$ kubectl delete service -l app=kubernetes-bootcamp -n s09-bootcamp
service "kubernetes-bootcamp" deleted from s09-bootcamp namespace
$ kubectl get services -n s09-bootcamp
No resources found in s09-bootcamp namespace.
$ minikube ssh -- curl -s --max-time 5 http://localhost:$NODE_PORT; echo "exit code: $?"
ssh: Process exited with status 7
exit code: 1
$ kubectl exec -n s09-bootcamp $POD_NAME -- curl -s http://localhost:8080
Hello Kubernetes bootcamp! | Running on: kubernetes-bootcamp-5cc66bcc9b-7rm97 | v=1
```

### Module 5: Scale the app

I exposed the Deployment again (it got a new NodePort, 31026) and scaled from 1 to 4 replicas:

```bash
$ kubectl expose deployment/kubernetes-bootcamp --type=NodePort --port 8080 -n s09-bootcamp
service/kubernetes-bootcamp exposed
$ kubectl get deployments -n s09-bootcamp
NAME                  READY   UP-TO-DATE   AVAILABLE   AGE
kubernetes-bootcamp   1/1     1            1           2m17s
$ kubectl get rs -n s09-bootcamp
NAME                             DESIRED   CURRENT   READY   AGE
kubernetes-bootcamp-5cc66bcc9b   1         1         1       2m17s
$ kubectl scale deployments/kubernetes-bootcamp --replicas=4 -n s09-bootcamp
deployment.apps/kubernetes-bootcamp scaled
$ kubectl rollout status deployment/kubernetes-bootcamp -n s09-bootcamp
Waiting for deployment "kubernetes-bootcamp" rollout to finish: 1 of 4 updated replicas are available...
Waiting for deployment "kubernetes-bootcamp" rollout to finish: 2 of 4 updated replicas are available...
Waiting for deployment "kubernetes-bootcamp" rollout to finish: 3 of 4 updated replicas are available...
deployment "kubernetes-bootcamp" successfully rolled out
$ kubectl get deployments -n s09-bootcamp
NAME                  READY   UP-TO-DATE   AVAILABLE   AGE
kubernetes-bootcamp   4/4     4            4           2m18s
$ kubectl get pods -o wide -n s09-bootcamp
NAME                                   READY   STATUS    RESTARTS   AGE     IP            NODE       NOMINATED NODE   READINESS GATES
kubernetes-bootcamp-5cc66bcc9b-7q87p   1/1     Running   0          1s      10.244.0.19   minikube   <none>           <none>
kubernetes-bootcamp-5cc66bcc9b-7rm97   1/1     Running   0          2m18s   10.244.0.16   minikube   <none>           <none>
kubernetes-bootcamp-5cc66bcc9b-v2qhd   1/1     Running   0          1s      10.244.0.18   minikube   <none>           <none>
kubernetes-bootcamp-5cc66bcc9b-xvnx8   1/1     Running   0          1s      10.244.0.17   minikube   <none>           <none>
$ kubectl describe deployments/kubernetes-bootcamp -n s09-bootcamp | sed -n '/^Events:/,$p'
Events:
  Type    Reason             Age    From                   Message
  ----    ------             ----   ----                   -------
  Normal  ScalingReplicaSet  2m18s  deployment-controller  Scaled up replica set kubernetes-bootcamp-5cc66bcc9b from 0 to 1
  Normal  ScalingReplicaSet  1s     deployment-controller  Scaled up replica set kubernetes-bootcamp-5cc66bcc9b from 1 to 4
$ kubectl get endpointslices -n s09-bootcamp
NAME                        ADDRESSTYPE   PORTS   ENDPOINTS                                         AGE
kubernetes-bootcamp-7t2xx   IPv4          8080    10.244.0.16,10.244.0.17,10.244.0.18 + 1 more...   1s
```

The ReplicaSet `5cc66bcc9b` went from 1 to 4 Pods (the new ones started in about a second because the image was already on the node) and the EndpointSlice now holds 4 addresses. Ten requests to the NodePort were spread across different Pods:

```bash
$ export NODE_PORT=$(kubectl get services/kubernetes-bootcamp -n s09-bootcamp -o go-template='{{(index .spec.ports 0).nodePort}}'); minikube ssh -- "for i in 1 2 3 4 5 6 7 8 9 10; do curl -s http://localhost:$NODE_PORT; done"
Hello Kubernetes bootcamp! | Running on: kubernetes-bootcamp-5cc66bcc9b-7q87p | v=1
Hello Kubernetes bootcamp! | Running on: kubernetes-bootcamp-5cc66bcc9b-7rm97 | v=1
Hello Kubernetes bootcamp! | Running on: kubernetes-bootcamp-5cc66bcc9b-7rm97 | v=1
Hello Kubernetes bootcamp! | Running on: kubernetes-bootcamp-5cc66bcc9b-7rm97 | v=1
Hello Kubernetes bootcamp! | Running on: kubernetes-bootcamp-5cc66bcc9b-7rm97 | v=1
Hello Kubernetes bootcamp! | Running on: kubernetes-bootcamp-5cc66bcc9b-7rm97 | v=1
Hello Kubernetes bootcamp! | Running on: kubernetes-bootcamp-5cc66bcc9b-xvnx8 | v=1
Hello Kubernetes bootcamp! | Running on: kubernetes-bootcamp-5cc66bcc9b-7q87p | v=1
Hello Kubernetes bootcamp! | Running on: kubernetes-bootcamp-5cc66bcc9b-7rm97 | v=1
Hello Kubernetes bootcamp! | Running on: kubernetes-bootcamp-5cc66bcc9b-7q87p | v=1
```

In this sample `v2qhd` was not hit. kube-proxy in iptables mode picks a backend at random for each new connection, so with 10 requests an uneven spread is normal.

Scaling down to 2: two Pods move to `Terminating` and the Deployment reports 2/2:

```bash
$ kubectl scale deployments/kubernetes-bootcamp --replicas=2 -n s09-bootcamp
deployment.apps/kubernetes-bootcamp scaled
$ sleep 5; kubectl get deployments -n s09-bootcamp
NAME                  READY   UP-TO-DATE   AVAILABLE   AGE
kubernetes-bootcamp   2/2     2            2           2m29s
$ kubectl get pods -o wide -n s09-bootcamp
NAME                                   READY   STATUS        RESTARTS   AGE     IP            NODE       NOMINATED NODE   READINESS GATES
kubernetes-bootcamp-5cc66bcc9b-7q87p   1/1     Running       0          12s     10.244.0.19   minikube   <none>           <none>
kubernetes-bootcamp-5cc66bcc9b-7rm97   1/1     Running       0          2m29s   10.244.0.16   minikube   <none>           <none>
kubernetes-bootcamp-5cc66bcc9b-v2qhd   1/1     Terminating   0          12s     10.244.0.18   minikube   <none>           <none>
kubernetes-bootcamp-5cc66bcc9b-xvnx8   1/1     Terminating   0          12s     10.244.0.17   minikube   <none>           <none>
```

### Module 6: Rolling update and rollback

I scaled back to 4 replicas (the tutorial starts this module with 4) and checked the current image:

```bash
$ kubectl scale deployments/kubernetes-bootcamp --replicas=4 -n s09-bootcamp && kubectl rollout status deployment/kubernetes-bootcamp -n s09-bootcamp
deployment.apps/kubernetes-bootcamp scaled
Waiting for deployment "kubernetes-bootcamp" rollout to finish: 2 of 4 updated replicas are available...
Waiting for deployment "kubernetes-bootcamp" rollout to finish: 3 of 4 updated replicas are available...
deployment "kubernetes-bootcamp" successfully rolled out
$ kubectl describe pods -n s09-bootcamp | grep -E '^Name:|^    Image:'
Name:             kubernetes-bootcamp-5cc66bcc9b-7q87p
    Image:          gcr.io/google-samples/kubernetes-bootcamp:v1
Name:             kubernetes-bootcamp-5cc66bcc9b-7rm97
    Image:          gcr.io/google-samples/kubernetes-bootcamp:v1
...
```

I started a `kubectl get pods -w` in the background (each line prefixed with the time it arrived) and then ran the tutorial's update command:

```bash
$ kubectl set image deployments/kubernetes-bootcamp kubernetes-bootcamp=docker.io/jocatalin/kubernetes-bootcamp:v2 -n s09-bootcamp
deployment.apps/kubernetes-bootcamp image updated
$ kubectl rollout status deployment/kubernetes-bootcamp -n s09-bootcamp --timeout=120s
Waiting for deployment "kubernetes-bootcamp" rollout to finish: 1 out of 4 new replicas have been updated...
Waiting for deployment "kubernetes-bootcamp" rollout to finish: 2 out of 4 new replicas have been updated...
Waiting for deployment "kubernetes-bootcamp" rollout to finish: 2 out of 4 new replicas have been updated...
Waiting for deployment "kubernetes-bootcamp" rollout to finish: 2 out of 4 new replicas have been updated...
Waiting for deployment "kubernetes-bootcamp" rollout to finish: 2 out of 4 new replicas have been updated...
error: timed out waiting for the condition
```

The rollout got stuck. The two new Pods could not pull the image because **Docker Hub refused the pull with `429 Too Many Requests`** (anonymous pull rate limit on this network):

```bash
$ kubectl describe pod kubernetes-bootcamp-5b97597885-c759m -n s09-bootcamp | sed -n '/^Events:/,$p' | cut -c1-420
Events:
  Type     Reason     Age                  From               Message
  ----     ------     ----                 ----               -------
  Normal   Scheduled  2m19s                default-scheduler  Successfully assigned s09-bootcamp/kubernetes-bootcamp-5b97597885-c759m to minikube
  Normal   Pulling    35s (x4 over 2m18s)  kubelet            spec.containers{kubernetes-bootcamp}: Pulling image "docker.io/jocatalin/kubernetes-bootcamp:v2"
  Warning  Failed     32s (x4 over 2m16s)  kubelet            spec.containers{kubernetes-bootcamp}: Failed to pull image "docker.io/jocatalin/kubernetes-bootcamp:v2": failed to pull and unpack image "docker.io/jocatalin/kubernetes-bootcamp:v2": failed to resolve reference "docker.io/jocatalin/kubernetes-bootcamp:v2": unexpected status from HEAD request to https://registry-1.docker.io/v2/jocatalin/kubernetes-bootcamp/
  Warning  Failed     32s (x4 over 2m16s)  kubelet            spec.containers{kubernetes-bootcamp}: Error: ErrImagePull
  Normal   BackOff    7s (x7 over 2m16s)   kubelet            spec.containers{kubernetes-bootcamp}: Back-off pulling image "docker.io/jocatalin/kubernetes-bootcamp:v2"
  Warning  Failed     7s (x7 over 2m16s)   kubelet            spec.containers{kubernetes-bootcamp}: Error: ImagePullBackOff
```

The describe output is cut at the terminal width; the event list shows the full reason:

```bash
$ kubectl get events -n s09-bootcamp --field-selector reason=Failed 2>&1 | head -5 | cut -c1-500
LAST SEEN   TYPE      REASON   OBJECT                                     MESSAGE
24s         Warning   Failed   pod/kubernetes-bootcamp-5b97597885-c759m   Failed to pull image "docker.io/jocatalin/kubernetes-bootcamp:v2": failed to pull and unpack image "docker.io/jocatalin/kubernetes-bootcamp:v2": failed to resolve reference "docker.io/jocatalin/kubernetes-bootcamp:v2": unexpected status from HEAD request to https://registry-1.docker.io/v2/jocatalin/kubernetes-bootcamp/manifests/v2: 429 Too Many Requests
24s         Warning   Failed   pod/kubernetes-bootcamp-5b97597885-c759m   Error: ErrImagePull
11s         Warning   Failed   pod/kubernetes-bootcamp-5b97597885-c759m   Error: ImagePullBackOff
...
```

```bash
$ kubectl get pods -n s09-bootcamp
NAME                                   READY   STATUS             RESTARTS   AGE
kubernetes-bootcamp-5b97597885-c759m   0/1     ErrImagePull       0          2m7s
kubernetes-bootcamp-5b97597885-dqtm2   0/1     ImagePullBackOff   0          2m7s
kubernetes-bootcamp-5cc66bcc9b-7q87p   1/1     Running            0          2m31s
kubernetes-bootcamp-5cc66bcc9b-7rm97   1/1     Running            0          4m48s
kubernetes-bootcamp-5cc66bcc9b-s2hxt   1/1     Running            0          2m9s
$ kubectl get rs -n s09-bootcamp
NAME                             DESIRED   CURRENT   READY   AGE
kubernetes-bootcamp-5b97597885   2         2         0       2m7s
kubernetes-bootcamp-5cc66bcc9b   3         3         3       4m48s
```

This is the rolling update protecting me: the default strategy (25% max unavailable, 25% max surge) only took one old Pod down, three v1 Pods kept serving, and the broken ReplicaSet `5b97597885` never became ready. Excerpt of the watch at that point:

```text
23:19:43  kubernetes-bootcamp-5b97597885-c759m   0/1     Pending       0          0s
23:19:43  kubernetes-bootcamp-5b97597885-c759m   0/1     Pending       0          0s
23:19:43  kubernetes-bootcamp-5cc66bcc9b-ggt7q   1/1     Terminating   0          2s
23:19:43  kubernetes-bootcamp-5b97597885-dqtm2   0/1     Pending       0          0s
23:19:43  kubernetes-bootcamp-5b97597885-c759m   0/1     ContainerCreating   0          0s
23:19:43  kubernetes-bootcamp-5b97597885-dqtm2   0/1     Pending             0          0s
23:19:43  kubernetes-bootcamp-5cc66bcc9b-ggt7q   1/1     Terminating         0          2s
23:19:43  kubernetes-bootcamp-5b97597885-dqtm2   0/1     ContainerCreating   0          0s
23:19:44  kubernetes-bootcamp-5b97597885-c759m   0/1     ContainerCreating   0          1s
23:19:44  kubernetes-bootcamp-5b97597885-dqtm2   0/1     ContainerCreating   0          1s
23:19:46  kubernetes-bootcamp-5b97597885-c759m   0/1     ErrImagePull        0          3s
23:19:48  kubernetes-bootcamp-5b97597885-dqtm2   0/1     ErrImagePull        0          5s
```

To finish the module I pointed the Deployment at the same `jocatalin/kubernetes-bootcamp:v2` image through Google's Docker Hub mirror (`mirror.gcr.io`), which did not rate-limit me. Later, once the Docker Hub limit had reset, I confirmed both references point to the identical image digest:

```bash
$ docker buildx imagetools inspect mirror.gcr.io/jocatalin/kubernetes-bootcamp:v2 | grep Digest
Digest:    sha256:fb1a3ced00cecfc1f83f18ab5cd14199e30adc1b49aa4244f5d65ad3f5feb2a5
$ docker buildx imagetools inspect docker.io/jocatalin/kubernetes-bootcamp:v2 | grep Digest
Digest:    sha256:fb1a3ced00cecfc1f83f18ab5cd14199e30adc1b49aa4244f5d65ad3f5feb2a5
```

```bash
$ kubectl set image deployments/kubernetes-bootcamp kubernetes-bootcamp=mirror.gcr.io/jocatalin/kubernetes-bootcamp:v2 -n s09-bootcamp
deployment.apps/kubernetes-bootcamp image updated
$ kubectl rollout status deployment/kubernetes-bootcamp -n s09-bootcamp --timeout=180s
Waiting for deployment "kubernetes-bootcamp" rollout to finish: 0 out of 4 new replicas have been updated...
Waiting for deployment "kubernetes-bootcamp" rollout to finish: 2 out of 4 new replicas have been updated...
Waiting for deployment "kubernetes-bootcamp" rollout to finish: 2 out of 4 new replicas have been updated...
Waiting for deployment "kubernetes-bootcamp" rollout to finish: 2 out of 4 new replicas have been updated...
Waiting for deployment "kubernetes-bootcamp" rollout to finish: 2 out of 4 new replicas have been updated...
Waiting for deployment "kubernetes-bootcamp" rollout to finish: 2 out of 4 new replicas have been updated...
Waiting for deployment "kubernetes-bootcamp" rollout to finish: 2 out of 4 new replicas have been updated...
Waiting for deployment "kubernetes-bootcamp" rollout to finish: 3 out of 4 new replicas have been updated...
Waiting for deployment "kubernetes-bootcamp" rollout to finish: 3 out of 4 new replicas have been updated...
Waiting for deployment "kubernetes-bootcamp" rollout to finish: 3 out of 4 new replicas have been updated...
Waiting for deployment "kubernetes-bootcamp" rollout to finish: 1 old replicas are pending termination...
Waiting for deployment "kubernetes-bootcamp" rollout to finish: 1 old replicas are pending termination...
Waiting for deployment "kubernetes-bootcamp" rollout to finish: 3 of 4 updated replicas are available...
deployment "kubernetes-bootcamp" successfully rolled out
$ kubectl get pods -n s09-bootcamp
NAME                                   READY   STATUS        RESTARTS   AGE
kubernetes-bootcamp-5448ddd47b-cs7qq   1/1     Running       0          4s
kubernetes-bootcamp-5448ddd47b-qf749   1/1     Running       0          4s
kubernetes-bootcamp-5448ddd47b-qzzlg   1/1     Running       0          0s
kubernetes-bootcamp-5448ddd47b-rjfj2   1/1     Running       0          1s
kubernetes-bootcamp-5cc66bcc9b-7q87p   1/1     Terminating   0          2m47s
kubernetes-bootcamp-5cc66bcc9b-7rm97   1/1     Terminating   0          5m4s
kubernetes-bootcamp-5cc66bcc9b-s2hxt   1/1     Terminating   0          2m25s
$ kubectl get rs -n s09-bootcamp
NAME                             DESIRED   CURRENT   READY   AGE
kubernetes-bootcamp-5448ddd47b   4         4         4       4s
kubernetes-bootcamp-5b97597885   0         0         0       2m23s
kubernetes-bootcamp-5cc66bcc9b   0         0         0       5m4s
$ kubectl describe pods -n s09-bootcamp | grep -E '^    Image:'
    Image:          mirror.gcr.io/jocatalin/kubernetes-bootcamp:v2
    Image:          mirror.gcr.io/jocatalin/kubernetes-bootcamp:v2
    Image:          mirror.gcr.io/jocatalin/kubernetes-bootcamp:v2
    Image:          mirror.gcr.io/jocatalin/kubernetes-bootcamp:v2
    Image:          gcr.io/google-samples/kubernetes-bootcamp:v1
    Image:          gcr.io/google-samples/kubernetes-bootcamp:v1
    Image:          gcr.io/google-samples/kubernetes-bootcamp:v1
```

Excerpt of the watch during this rollout. The broken Pods were removed first, then new v2 Pods (`5448ddd47b-*`) became `Running` and only after that were old v1 Pods sent to `Terminating`, one batch at a time:

```text
23:22:02  kubernetes-bootcamp-5b97597885-dqtm2   0/1     Terminating         0          2m19s
23:22:02  kubernetes-bootcamp-5b97597885-c759m   0/1     Terminating         0          2m19s
23:22:02  kubernetes-bootcamp-5448ddd47b-qf749   0/1     Pending             0          0s
23:22:02  kubernetes-bootcamp-5b97597885-dqtm2   0/1     Terminating         0          2m19s
23:22:02  kubernetes-bootcamp-5448ddd47b-cs7qq   0/1     Pending             0          0s
23:22:02  kubernetes-bootcamp-5448ddd47b-qf749   0/1     Pending             0          0s
23:22:02  kubernetes-bootcamp-5448ddd47b-cs7qq   0/1     Pending             0          0s
23:22:02  kubernetes-bootcamp-5b97597885-c759m   0/1     Terminating         0          2m19s
23:22:02  kubernetes-bootcamp-5448ddd47b-qf749   0/1     ContainerCreating   0          0s
23:22:02  kubernetes-bootcamp-5448ddd47b-cs7qq   0/1     ContainerCreating   0          0s
23:22:02  kubernetes-bootcamp-5b97597885-dqtm2   0/1     Terminating         0          2m19s
23:22:02  kubernetes-bootcamp-5b97597885-c759m   0/1     Terminating         0          2m19s
23:22:03  kubernetes-bootcamp-5448ddd47b-qf749   0/1     ContainerCreating   0          1s
23:22:03  kubernetes-bootcamp-5448ddd47b-cs7qq   0/1     ContainerCreating   0          1s
23:22:03  kubernetes-bootcamp-5b97597885-dqtm2   0/1     ContainerStatusUnknown   0          2m20s
23:22:03  kubernetes-bootcamp-5b97597885-dqtm2   0/1     ContainerStatusUnknown   0          2m20s
23:22:03  kubernetes-bootcamp-5b97597885-dqtm2   0/1     ContainerStatusUnknown   0          2m20s
23:22:03  kubernetes-bootcamp-5b97597885-c759m   0/1     ContainerStatusUnknown   0          2m20s
23:22:03  kubernetes-bootcamp-5b97597885-c759m   0/1     ContainerStatusUnknown   0          2m20s
23:22:03  kubernetes-bootcamp-5b97597885-c759m   0/1     ContainerStatusUnknown   0          2m20s
23:22:05  kubernetes-bootcamp-5448ddd47b-qf749   1/1     Running                  0          3s
23:22:05  kubernetes-bootcamp-5cc66bcc9b-7rm97   1/1     Terminating              0          5m3s
23:22:05  kubernetes-bootcamp-5cc66bcc9b-7rm97   1/1     Terminating              0          5m3s
23:22:05  kubernetes-bootcamp-5448ddd47b-rjfj2   0/1     Pending                  0          0s
23:22:05  kubernetes-bootcamp-5448ddd47b-rjfj2   0/1     Pending                  0          0s
23:22:05  kubernetes-bootcamp-5448ddd47b-rjfj2   0/1     ContainerCreating        0          0s
23:22:06  kubernetes-bootcamp-5448ddd47b-rjfj2   0/1     ContainerCreating        0          1s
23:22:06  kubernetes-bootcamp-5448ddd47b-cs7qq   1/1     Running                  0          4s
23:22:06  kubernetes-bootcamp-5cc66bcc9b-7q87p   1/1     Terminating              0          2m47s
23:22:06  kubernetes-bootcamp-5448ddd47b-rjfj2   1/1     Running                  0          1s
23:22:06  kubernetes-bootcamp-5448ddd47b-qzzlg   0/1     Pending                  0          0s
23:22:06  kubernetes-bootcamp-5cc66bcc9b-7q87p   1/1     Terminating              0          2m47s
23:22:06  kubernetes-bootcamp-5448ddd47b-qzzlg   0/1     Pending                  0          0s
23:22:06  kubernetes-bootcamp-5cc66bcc9b-s2hxt   1/1     Terminating              0          2m25s
23:22:06  kubernetes-bootcamp-5448ddd47b-qzzlg   0/1     ContainerCreating        0          0s
23:22:06  kubernetes-bootcamp-5cc66bcc9b-s2hxt   1/1     Terminating              0          2m25s
23:22:06  kubernetes-bootcamp-5448ddd47b-qzzlg   0/1     ContainerCreating        0          0s
23:22:06  kubernetes-bootcamp-5448ddd47b-qzzlg   1/1     Running                  0          0s
```

Verifying through the Service: every answer now says `v=2`:

```bash
$ kubectl describe services/kubernetes-bootcamp -n s09-bootcamp | grep -E 'NodePort|Endpoints'
Type:                     NodePort
NodePort:                 <unset>  31026/TCP
Endpoints:                10.244.0.32:8080,10.244.0.33:8080,10.244.0.34:8080 + 1 more...
$ export NODE_PORT=$(kubectl get services/kubernetes-bootcamp -n s09-bootcamp -o go-template='{{(index .spec.ports 0).nodePort}}'); minikube ssh -- "for i in 1 2 3 4 5; do curl -s http://localhost:$NODE_PORT; done"
Hello Kubernetes bootcamp! | Running on: kubernetes-bootcamp-5448ddd47b-rjfj2 | v=2
Hello Kubernetes bootcamp! | Running on: kubernetes-bootcamp-5448ddd47b-cs7qq | v=2
Hello Kubernetes bootcamp! | Running on: kubernetes-bootcamp-5448ddd47b-cs7qq | v=2
Hello Kubernetes bootcamp! | Running on: kubernetes-bootcamp-5448ddd47b-cs7qq | v=2
Hello Kubernetes bootcamp! | Running on: kubernetes-bootcamp-5448ddd47b-rjfj2 | v=2
$ kubectl rollout status deployments/kubernetes-bootcamp -n s09-bootcamp
deployment "kubernetes-bootcamp" successfully rolled out
$ kubectl rollout history deployments/kubernetes-bootcamp -n s09-bootcamp
deployment.apps/kubernetes-bootcamp 
REVISION  CHANGE-CAUSE
1         <none>
2         <none>
3         <none>
```

Next, the tutorial deploys a tag that does not exist (`v10`) to practise a rollback:

```bash
$ kubectl set image deployments/kubernetes-bootcamp kubernetes-bootcamp=gcr.io/google-samples/kubernetes-bootcamp:v10 -n s09-bootcamp
deployment.apps/kubernetes-bootcamp image updated
$ sleep 15; kubectl get deployments -n s09-bootcamp
NAME                  READY   UP-TO-DATE   AVAILABLE   AGE
kubernetes-bootcamp   3/4     2            3           5m47s
$ kubectl get pods -n s09-bootcamp
NAME                                   READY   STATUS         RESTARTS   AGE
kubernetes-bootcamp-5448ddd47b-cs7qq   1/1     Terminating    0          47s
kubernetes-bootcamp-5448ddd47b-qf749   1/1     Running        0          47s
kubernetes-bootcamp-5448ddd47b-qzzlg   1/1     Running        0          43s
kubernetes-bootcamp-5448ddd47b-rjfj2   1/1     Running        0          44s
kubernetes-bootcamp-556487b4d4-5mqsf   0/1     ErrImagePull   0          15s
kubernetes-bootcamp-556487b4d4-7zq5g   0/1     ErrImagePull   0          15s
```

```bash
$ kubectl describe pod kubernetes-bootcamp-556487b4d4-5mqsf -n s09-bootcamp | sed -n '/^Events:/,$p' | cut -c1-330
Events:
  Type     Reason     Age               From               Message
  ----     ------     ----              ----               -------
  Normal   Scheduled  22s               default-scheduler  Successfully assigned s09-bootcamp/kubernetes-bootcamp-556487b4d4-5mqsf to minikube
  Normal   BackOff    20s               kubelet            spec.containers{kubernetes-bootcamp}: Back-off pulling image "gcr.io/google-samples/kubernetes-bootcamp:v10"
  Warning  Failed     20s               kubelet            spec.containers{kubernetes-bootcamp}: Error: ImagePullBackOff
  Normal   Pulling    6s (x2 over 22s)  kubelet            spec.containers{kubernetes-bootcamp}: Pulling image "gcr.io/google-samples/kubernetes-bootcamp:v10"
  Warning  Failed     5s (x2 over 21s)  kubelet            spec.containers{kubernetes-bootcamp}: Failed to pull image "gcr.io/google-samples/kubernetes-bootcamp:v10": rpc error: code = NotFound desc = failed to pull and unpack image "gcr.io/google-samples/kubernetes-bootcamp:v10": failed to resolve reference "gcr.io/google-sampl
  Warning  Failed     5s (x2 over 21s)  kubelet            spec.containers{kubernetes-bootcamp}: Error: ErrImagePull
```

The message is cut by the terminal width, so I asked the runtime on the node directly. The root cause is that the tag does not exist (`NotFound`), not a rate limit this time:

```bash
$ minikube ssh -- sudo crictl pull gcr.io/google-samples/kubernetes-bootcamp:v10
E1007 18:09:43.752618  588028 log.go:32] "PullImage from image service failed" err="rpc error: code = NotFound desc = failed to pull and unpack image \"gcr.io/google-samples/kubernetes-bootcamp:v10\": failed to resolve reference \"gcr.io/google-samples/kubernetes-bootcamp:v10\": gcr.io/google-samples/kubernetes-bootcamp:v10: not found" image="gcr.io/google-samples/kubernetes-bootcamp:v10"
FATA[0000] pulling image: rpc error: code = NotFound desc = failed to pull and unpack image "gcr.io/google-samples/kubernetes-bootcamp:v10": failed to resolve reference "gcr.io/google-samples/kubernetes-bootcamp:v10": gcr.io/google-samples/kubernetes-bootcamp:v10: not found 
ssh: Process exited with status 1
```

Again only one old Pod was taken down (3/4 available) and the app kept serving. Rolling back:

```bash
$ kubectl rollout undo deployments/kubernetes-bootcamp -n s09-bootcamp
deployment.apps/kubernetes-bootcamp rolled back
$ kubectl rollout status deployments/kubernetes-bootcamp -n s09-bootcamp
Waiting for deployment "kubernetes-bootcamp" rollout to finish: 3 out of 4 new replicas have been updated...
Waiting for deployment "kubernetes-bootcamp" rollout to finish: 3 out of 4 new replicas have been updated...
Waiting for deployment "kubernetes-bootcamp" rollout to finish: 3 of 4 updated replicas are available...
Waiting for deployment "kubernetes-bootcamp" rollout to finish: 3 of 4 updated replicas are available...
Waiting for deployment "kubernetes-bootcamp" rollout to finish: 3 of 4 updated replicas are available...
deployment "kubernetes-bootcamp" successfully rolled out
$ sleep 20; kubectl get pods -n s09-bootcamp
NAME                                   READY   STATUS    RESTARTS   AGE
kubernetes-bootcamp-5448ddd47b-qf749   1/1     Running   0          75s
kubernetes-bootcamp-5448ddd47b-qzzlg   1/1     Running   0          71s
kubernetes-bootcamp-5448ddd47b-rjfj2   1/1     Running   0          72s
kubernetes-bootcamp-5448ddd47b-t8l9m   1/1     Running   0          21s
$ kubectl describe pods -n s09-bootcamp | grep -E '^    Image:'
    Image:          mirror.gcr.io/jocatalin/kubernetes-bootcamp:v2
    Image:          mirror.gcr.io/jocatalin/kubernetes-bootcamp:v2
    Image:          mirror.gcr.io/jocatalin/kubernetes-bootcamp:v2
    Image:          mirror.gcr.io/jocatalin/kubernetes-bootcamp:v2
$ kubectl rollout history deployments/kubernetes-bootcamp -n s09-bootcamp
deployment.apps/kubernetes-bootcamp 
REVISION  CHANGE-CAUSE
1         <none>
2         <none>
4         <none>
5         <none>
$ kubectl get rs -n s09-bootcamp -o wide
NAME                             DESIRED   CURRENT   READY   AGE     CONTAINERS            IMAGES                                           SELECTOR
kubernetes-bootcamp-5448ddd47b   4         4         4       75s     kubernetes-bootcamp   mirror.gcr.io/jocatalin/kubernetes-bootcamp:v2   app=kubernetes-bootcamp,pod-template-hash=5448ddd47b
kubernetes-bootcamp-556487b4d4   0         0         0       43s     kubernetes-bootcamp   gcr.io/google-samples/kubernetes-bootcamp:v10    app=kubernetes-bootcamp,pod-template-hash=556487b4d4
kubernetes-bootcamp-5b97597885   0         0         0       3m34s   kubernetes-bootcamp   docker.io/jocatalin/kubernetes-bootcamp:v2       app=kubernetes-bootcamp,pod-template-hash=5b97597885
kubernetes-bootcamp-5cc66bcc9b   0         0         0       6m15s   kubernetes-bootcamp   gcr.io/google-samples/kubernetes-bootcamp:v1     app=kubernetes-bootcamp,pod-template-hash=5cc66bcc9b
```

After `rollout undo` all 4 Pods run the v2 image again. The history shows that the undo re-used the old template and gave it a new revision number (revision 3 became 5), and every ReplicaSet the Deployment ever had is still there with 0 replicas, which is what makes rollback possible. The app answers `v=2` again:

```bash
$ export NODE_PORT=$(kubectl get services/kubernetes-bootcamp -n s09-bootcamp -o go-template='{{(index .spec.ports 0).nodePort}}'); minikube ssh -- "for i in 1 2 3; do curl -s http://localhost:$NODE_PORT; done"
Hello Kubernetes bootcamp! | Running on: kubernetes-bootcamp-5448ddd47b-t8l9m | v=2
Hello Kubernetes bootcamp! | Running on: kubernetes-bootcamp-5448ddd47b-rjfj2 | v=2
Hello Kubernetes bootcamp! | Running on: kubernetes-bootcamp-5448ddd47b-rjfj2 | v=2
```

## Cleanup

```bash
$ kubectl delete namespace s09-bootcamp s09-basics
namespace "s09-bootcamp" deleted
namespace "s09-basics" deleted
```

I also stopped the background `kubectl proxy`, port-forward and watch processes.

## What I learned

- A Minikube cluster with the docker driver is a single container that runs both the control plane (as static Pods) and the node components (kubelet and containerd as systemd services).
- The API server is the only component that talks to etcd; everything else (scheduler, controllers, kubelet, kubectl) works through the API server and watches for changes.
- `kubectl describe` Events are the quickest way to see why something is not working (scheduling, image pulls, probes).
- A Service gives a stable IP and NodePort, but with the docker driver on macOS I need `kubectl port-forward` (or a tunnel) to reach it from the host.
- A rolling update never takes the whole app down: when the new image could not be pulled (rate limit, then a bad tag) the old Pods kept serving and `kubectl rollout undo` brought the last good version back.
- On an arm64 Mac I have to check image architectures. Here an amd64-only image still ran because the VM has QEMU emulation, and Docker Hub rate limits are a real-world problem that registry mirrors solve.
