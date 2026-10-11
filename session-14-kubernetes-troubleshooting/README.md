# Session 14: Kubernetes Troubleshooting

**Name:** Vansh Srivastava
**Enrollment No.:** 24bcs10567
**Session:** 14

This session is about finding out why something in Kubernetes does not work, using a fixed order instead of guessing: `get` (what state?), `describe` and events (what did Kubernetes try?), `logs` (what does the app say?), `exec` (what does it look like from inside?), then test, fix and verify. I practised each command on the course demo Pods, then broke and fixed nine kinds of problems on the shared minikube cluster: the course "triage gauntlet" scenarios, the course Service/DNS examples, and a few cases I built myself. Finally I completed the course troubleshooting mini project.

Course material comes from https://github.com/Nency-Ravaliya/devops-heros (folder `session-14-kubernetes-troubleshooting`). Copied files say so in their header, with my changes.

## Folder structure

```text
session-14-kubernetes-troubleshooting/
├── README.md
├── .gitignore
├── 01-commands/                       # course demo pods from 01-kubectl-get ... 05-events
│   ├── namespace.yaml                 # s14-commands
│   └── get-demo.yaml, describe-demo.yaml, logs-demo.yaml, exec-demo.yaml, events-demo.yaml
├── scenarios/                         # course scenarios folder (triage gauntlet) + my fixes
│   ├── triage_all.sh                  # course script, unchanged
│   ├── scenario-1-crashloop/          # broken.yaml (course), fix-step1-env-only.yaml, fixed.yaml
│   ├── scenario-2-imagepull/          # broken.yaml (course), fixed.yaml
│   ├── scenario-3-pending/            # broken.yaml (course), fixed.yaml
│   ├── scenario-4-dns-failure/        # broken.yaml (course), postgres-db.yaml, fixed.yaml
│   └── scenario-5-oomkilled/          # broken.yaml (course), fixed.yaml
├── 02-common-issues/
│   ├── pending/                       # course 08-pending-pods (nodeSelector) broken + fixed
│   ├── containercreating/             # Pod stuck in ContainerCreating (missing ConfigMap + Secret volume)
│   ├── service-connectivity/          # course 09-service-dns files + client, fixed and wrong-port Services
│   ├── network-policy/                # default-deny NetworkPolicy blocking traffic + the allow rule
│   └── configuration/                 # env var pointing at a ConfigMap key that does not exist
└── 03-mini-project/                   # course mini project files + COURSE-INSTRUCTIONS.md
```

## Environment

- macOS on Apple Silicon (arm64), Docker via Colima, minikube v1.39.0, Kubernetes v1.37.0 (containerd), one shared node (6 CPU, ~10 GiB). CNI: kindnet. CoreDNS and metrics-server enabled.
- I worked only in my own namespaces (`s14-commands`, `s14-triage`, `s14-containercreating`, `s14-service`, `s14-netpol`, `s14-config`, `s14-mini`) and deleted them at the end.
- Images: Docker Hub answered `429 Too Many Requests` from this network (full error in the Session 12 README), so working images point to the AWS ECR Public mirror (`public.ecr.aws/docker/library/...`), and `curlimages/curl` to the same project's `quay.io/curl/curl`. The intentionally broken image references were also moved to the mirror, with the same wrong repository or tag. That way they fail for their real reason (`not found`), not because of the rate limit.
- The Task 1 outputs were captured on 2026-10-07. Task 2 and Task 3 were run on 2026-10-12, after a break in my work, so some ages show `4d`.

## Task 1: Commands

The five course demo Pods (`01-kubectl-get` to `05-events`) in their own namespace:

```bash
$ kubectl apply -f namespace.yaml && kubectl -n s14-commands apply -f get-demo.yaml -f describe-demo.yaml -f logs-demo.yaml -f exec-demo.yaml -f events-demo.yaml
namespace/s14-commands created
pod/get-demo created
pod/describe-demo created
pod/logs-demo created
pod/exec-demo created
pod/events-demo created
$ kubectl -n s14-commands wait --for=condition=Ready pod --all --timeout=120s
pod/describe-demo condition met
pod/events-demo condition met
pod/exec-demo condition met
pod/get-demo condition met
pod/logs-demo condition met
```

### kubectl get

When to use: always first. It is a quick summary of the current state (STATUS, READY, RESTARTS, AGE), so I can see *what* is wrong and *which* object to look at.

```bash
$ kubectl -n s14-commands get pods
NAME            READY   STATUS    RESTARTS   AGE
describe-demo   1/1     Running   0          1s
events-demo     1/1     Running   0          1s
exec-demo       1/1     Running   0          1s
get-demo        1/1     Running   0          1s
logs-demo       1/1     Running   0          1s
$ kubectl -n s14-commands get pods --show-labels
NAME            READY   STATUS    RESTARTS   AGE   LABELS
describe-demo   1/1     Running   0          1s    app=describe-demo
events-demo     1/1     Running   0          1s    <none>
exec-demo       1/1     Running   0          1s    <none>
get-demo        1/1     Running   0          1s    app=get-demo
logs-demo       1/1     Running   0          1s    <none>
$ kubectl -n s14-commands get pod get-demo -o jsonpath="{.status.phase} {.status.podIP} {.spec.nodeName}{\"\n\"}"
Running 10.244.0.34 minikube
$ kubectl get nodes
NAME       STATUS   ROLES           AGE   VERSION
minikube   Ready    control-plane   47m   v1.37.0
```

`-w` keeps watching. In a second terminal I deleted `get-demo` and created it again, and the watch showed every phase change:

```bash
$ kubectl -n s14-commands get pods -w
# (second terminal: kubectl -n s14-commands delete pod get-demo && kubectl -n s14-commands apply -f get-demo.yaml)
NAME            READY   STATUS    RESTARTS   AGE
describe-demo   1/1     Running   0          10s
events-demo     1/1     Running   0          10s
exec-demo       1/1     Running   0          10s
get-demo        1/1     Running   0          10s
logs-demo       1/1     Running   0          10s
get-demo        1/1     Terminating   0          12s
get-demo        1/1     Terminating   0          12s
get-demo        0/1     Completed     0          12s
get-demo        0/1     Completed     0          13s
get-demo        0/1     Completed     0          13s
get-demo        0/1     Pending       0          0s
get-demo        0/1     Pending       0          0s
get-demo        0/1     ContainerCreating   0          0s
get-demo        0/1     ContainerCreating   0          0s
get-demo        1/1     Running             0          0s
```

### kubectl get -o wide

When to use: when I need the Pod IP and the node, for example to test a Pod directly (bypassing the Service), to compare with Service endpoints, or to see if problems are limited to one node.

```bash
$ kubectl -n s14-commands get pods -o wide
NAME            READY   STATUS    RESTARTS   AGE   IP            NODE       NOMINATED NODE   READINESS GATES
describe-demo   1/1     Running   0          1s    10.244.0.33   minikube   <none>           <none>
events-demo     1/1     Running   0          1s    10.244.0.37   minikube   <none>           <none>
exec-demo       1/1     Running   0          1s    10.244.0.36   minikube   <none>           <none>
get-demo        1/1     Running   0          1s    10.244.0.34   minikube   <none>           <none>
logs-demo       1/1     Running   0          1s    10.244.0.35   minikube   <none>           <none>
$ kubectl get nodes -o wide
NAME       STATUS   ROLES           AGE   VERSION   INTERNAL-IP    EXTERNAL-IP   OS-IMAGE                         KERNEL-VERSION              CONTAINER-RUNTIME
minikube   Ready    control-plane   47m   v1.37.0   192.168.49.2   <none>        Debian GNU/Linux 12 (bookworm)   6.8.0-117-generic (arm64)   containerd://2.3.4
```

### kubectl describe

When to use: once `get` shows a bad state. It shows the full picture of one object: image, state and last state with exit codes, restart count, probes, env, mounts, conditions, and the recent events at the bottom.

```bash
$ kubectl -n s14-commands describe pod describe-demo
Name:             describe-demo
Namespace:        s14-commands
Priority:         0
Service Account:  default
Node:             minikube/192.168.49.2
Start Time:       Wed, 07 Oct 2026 23:53:47 +0530
Labels:           app=describe-demo
Annotations:      <none>
Status:           Running
IP:               10.244.0.33
IPs:
  IP:  10.244.0.33
Containers:
  nginx:
    Container ID:   containerd://89b32ee845b48ca2c6603f5b610180c01fd5ecdcc4af18205d1097147bd925b0
    Image:          public.ecr.aws/docker/library/nginx:1.27
    Image ID:       public.ecr.aws/docker/library/nginx@sha256:6784fb0834aa7dbbe12e3d7471e69c290df3e6ba810dc38b34ae33d3c1c05f7d
    Port:           80/TCP
    Host Port:      0/TCP
    State:          Running
      Started:      Wed, 07 Oct 2026 23:53:48 +0530
    Ready:          True
    Restart Count:  0
    Environment:    <none>
    Mounts:
      /var/run/secrets/kubernetes.io/serviceaccount from kube-api-access-pzdpr (ro)
Conditions:
  Type                        Status
  PodReadyToStartContainers   True 
  Initialized                 True 
  Ready                       True 
  ContainersReady             True 
  PodScheduled                True 
...
QoS Class:                   BestEffort
Node-Selectors:              <none>
...
Events:
  Type    Reason     Age   From               Message
  ----    ------     ----  ----               -------
  Normal  Scheduled  23s   default-scheduler  Successfully assigned s14-commands/describe-demo to minikube
  Normal  Pulled     23s   kubelet            spec.containers{nginx}: Container image "public.ecr.aws/docker/library/nginx:1.27" already present on machine and can be accessed by the pod
  Normal  Created    23s   kubelet            spec.containers{nginx}: Container created
  Normal  Started    22s   kubelet            spec.containers{nginx}: Container started
```

### kubectl logs

When to use: when the container starts but misbehaves or exits. It shows what the application wrote to stdout/stderr. `--previous` shows the last crashed instance (the key command for CrashLoopBackOff), `-c` picks a container in multi-container Pods, `--since` / `--tail` limit the output, and `-f` follows.

```bash
$ kubectl -n s14-commands logs logs-demo --tail=6
Application is running
Application is healthy
Application is healthy
Application is healthy
Application is healthy
Application is healthy
$ kubectl -n s14-commands logs logs-demo --since=12s --timestamps
2026-10-07T18:24:02.936777235Z Application is healthy
2026-10-07T18:24:07.937162125Z Application is healthy
$ kubectl -n s14-commands logs logs-demo -c app --tail=1
Application is healthy
$ kubectl -n s14-commands logs logs-demo --previous
Error from server (BadRequest): previous terminated container "app" in pod "logs-demo" not found
```

The last error is expected: this container never restarted, so there is no previous instance. In Task 2 `--previous` is what shows the crash reasons.

### kubectl exec

When to use: when the container is running and I want to test from inside it: is the app answering on localhost, what config and DNS settings does it see, which files are there. If `localhost` works but the Service does not, the problem is outside the container.

```bash
$ kubectl -n s14-commands exec exec-demo -- hostname
exec-demo
$ kubectl -n s14-commands exec exec-demo -- ls /usr/share/nginx/html
50x.html
index.html
$ kubectl -n s14-commands exec exec-demo -- curl -s -o /dev/null -w "HTTP %{http_code} from localhost inside the container\n" localhost
HTTP 200 from localhost inside the container
$ kubectl -n s14-commands exec exec-demo -- cat /etc/resolv.conf
search s14-commands.svc.cluster.local svc.cluster.local cluster.local
nameserver 10.96.0.10
options ndots:5
$ kubectl -n s14-commands exec exec-demo -- sh -c "nginx -T 2>/dev/null | grep -E \"^\s*(listen|root|server_name)\" | sort -u"
        root   /usr/share/nginx/html;
    listen       80;
    listen  [::]:80;
    server_name  localhost;
```

### kubectl events (and get events)

When to use: to see what Kubernetes itself tried and what failed (scheduling, image pulls, volume mounts, probe failures, back-offs), for one object or for a whole namespace. Events are kept for about an hour, so look early.

```bash
$ kubectl -n s14-commands get events --sort-by=.lastTimestamp | tail -8
29s         Normal   Started     pod/exec-demo       Container started
29s         Normal   Started     pod/describe-demo   Container started
29s         Normal   Started     pod/logs-demo       Container started
18s         Normal   Killing     pod/get-demo        Stopping container nginx
17s         Normal   Scheduled   pod/get-demo        Successfully assigned s14-commands/get-demo to minikube
17s         Normal   Pulled      pod/get-demo        Container image "public.ecr.aws/docker/library/nginx:1.27" already present on machine and can be accessed by the pod
17s         Normal   Created     pod/get-demo        Container created
17s         Normal   Started     pod/get-demo        Container started
$ kubectl -n s14-commands events --for pod/events-demo
LAST SEEN   TYPE     REASON      OBJECT            MESSAGE
30s         Normal   Scheduled   Pod/events-demo   Successfully assigned s14-commands/events-demo to minikube
30s         Normal   Pulled      Pod/events-demo   Container image "public.ecr.aws/docker/library/nginx:1.27" already present on machine and can be accessed by the pod
30s         Normal   Created     Pod/events-demo   Container created
29s         Normal   Started     Pod/events-demo   Container started
$ kubectl -n s14-commands get events --field-selector type=Warning
No resources found in s14-commands namespace.
```

No warnings here, because these Pods are healthy. In Task 2 warnings are where most root causes show up first.

### kubectl explain

When to use: when I am not sure what a field means, what values it accepts, or where it goes in the YAML. It reads the schema from the API server, so it matches the cluster's version.

```bash
$ kubectl explain pod.spec.containers.imagePullPolicy
KIND:       Pod
VERSION:    v1

FIELD: imagePullPolicy <string>
ENUM:
    Always
    IfNotPresent
    Never

DESCRIPTION:
    Image pull policy. One of Always, Never, IfNotPresent. Defaults to Always if
    :latest tag is specified, or IfNotPresent otherwise. Cannot be updated. More
    info: https://kubernetes.io/docs/concepts/containers/images#updating-images
...
$ kubectl explain deployment.spec.strategy
GROUP:      apps
KIND:       Deployment
VERSION:    v1

FIELD: strategy <DeploymentStrategy>


DESCRIPTION:
    The deployment strategy to use to replace existing pods with new ones.
    DeploymentStrategy describes how to replace existing pods with new ones.
    
FIELDS:
  rollingUpdate	<RollingUpdateDeployment>
    Rolling update config params. Present only if DeploymentStrategyType =
    RollingUpdate.

  type	<string>
  enum: Recreate, RollingUpdate
    Type of deployment. Can be "Recreate" or "RollingUpdate". Default is
    RollingUpdate.
...
$ kubectl explain pod.spec.containers.resources --recursive | head -20
KIND:       Pod
VERSION:    v1

FIELD: resources <ResourceRequirements>


DESCRIPTION:
    Compute Resources required by this container. Cannot be updated. More info:
    https://kubernetes.io/docs/concepts/configuration/manage-resources-containers/
    ResourceRequirements describes the compute resource requirements.
    
FIELDS:
  claims	<[]ResourceClaim>
    name	<string> -required-
    request	<string>
  limits	<map[string]Quantity>
  requests	<map[string]Quantity>

```

### kubectl top

When to use: to check real CPU and memory usage against requests and limits, for example a container close to its memory limit (OOMKilled risk), a Pod using a lot of CPU, or a full node. It needs metrics-server. Right after the Pods started it had nothing yet:

```bash
$ kubectl -n s14-commands top pods
error: metrics not available yet
```

Later run (same Pods):

```bash
$ kubectl top nodes
NAME       CPU(cores)   CPU(%)   MEMORY(bytes)   MEMORY(%)   
minikube   409m         6%       3680Mi          37%         
$ kubectl -n s14-commands top pods
NAME            CPU(cores)   MEMORY(bytes)   
describe-demo   0m           5Mi             
events-demo     0m           5Mi             
exec-demo       0m           13Mi            
get-demo        0m           5Mi             
logs-demo       1m           0Mi             
$ kubectl -n s14-commands top pod exec-demo --containers
POD         NAME    CPU(cores)   MEMORY(bytes)   
exec-demo   nginx   0m           13Mi            
$ kubectl -n s14-commands top pods --sort-by=memory
NAME            CPU(cores)   MEMORY(bytes)   
exec-demo       0m           13Mi            
get-demo        0m           5Mi             
events-demo     0m           5Mi             
describe-demo   0m           5Mi             
logs-demo       1m           0Mi             
```

## Task 2: Troubleshoot common issues

For every issue I followed the same steps: **identify** (`get`), **investigate** (`describe`, events, `logs`, `exec`, tests), **root cause**, **fix**, **verify**.

The course `scenarios/` folder deploys five broken Pods at once with `triage_all.sh`. The script runs `kubectl apply` without a namespace, and I must not change the shared kubeconfig's default namespace. So I ran the unchanged script with a private copy of the kubeconfig whose context points at `s14-triage` (`$KCFG` is that copy, kept outside the repo):

```bash
$ kubectl create namespace s14-triage
namespace/s14-triage created
...
$ kubectl config view --minify --flatten > $KCFG && KUBECONFIG=$KCFG kubectl config set-context --current --namespace=s14-triage
Context "minikube" modified.
$ KUBECONFIG=$KCFG bash triage_all.sh
==================================================
      KUBERNETES INCIDENT TRIAGE GAUNTLET         
==================================================
Deploying 5 intentionally broken production workloads...

pod/fail-1-crashloop-pod created
pod/fail-2-imagepull-pod created
pod/fail-3-pending-pod created
pod/fail-4-dns-failure-pod created
pod/fail-5-oomkilled-pod created

Workloads deployed! Sleeping 5s to allow states to settle...

=== CURRENT CLUSTER CARNAGE ===
NAME                     READY   STATUS         RESTARTS     AGE
fail-1-crashloop-pod     0/1     Error          1 (5s ago)   5s
fail-2-imagepull-pod     0/1     ErrImagePull   0            5s
fail-3-pending-pod       0/1     Pending        0            5s
fail-4-dns-failure-pod   1/1     Running        0            5s
fail-5-oomkilled-pod     0/1     OOMKilled      1 (4s ago)   5s

==================================================
Your mission: Diagnose and fix each of the 5 pods!
Follow the diagnostic guide in README.md!
==================================================
$ kubectl -n s14-triage get pods -l tier=triage-gauntlet -o wide
NAME                     READY   STATUS         RESTARTS      AGE   IP            NODE       NOMINATED NODE   READINESS GATES
fail-1-crashloop-pod     0/1     Error          3 (22s ago)   35s   10.244.0.53   minikube   <none>           <none>
fail-2-imagepull-pod     0/1     ErrImagePull   0             35s   10.244.0.54   minikube   <none>           <none>
fail-3-pending-pod       0/1     Pending        0             35s   <none>        <none>     <none>           <none>
fail-4-dns-failure-pod   1/1     Running        0             35s   10.244.0.55   minikube   <none>           <none>
fail-5-oomkilled-pod     0/1     OOMKilled      2 (34s ago)   35s   10.244.0.56   minikube   <none>           <none>
```

### Issue 1: CrashLoopBackOff (course scenario 1)

**Identify and investigate**

```bash
$ kubectl -n s14-triage get pod fail-1-crashloop-pod
NAME                   READY   STATUS             RESTARTS      AGE
fail-1-crashloop-pod   0/1     CrashLoopBackOff   4 (70s ago)   2m30s
$ kubectl -n s14-triage describe pod fail-1-crashloop-pod | sed -n "/^    State/,/^    Restart Count/p;/^    Environment/p;/^Events/,\$p"
    State:          Waiting
      Reason:       CrashLoopBackOff
    Last State:     Terminated
      Reason:       Error
      Exit Code:    1
      Started:      Mon, 12 Oct 2026 01:44:07 +0530
      Finished:     Mon, 12 Oct 2026 01:44:07 +0530
    Ready:          False
    Restart Count:  4
    Environment:    <none>
Events:
  Type     Reason     Age                  From               Message
  ----     ------     ----                 ----               -------
  Normal   Scheduled  2m30s                default-scheduler  Successfully assigned s14-triage/fail-1-crashloop-pod to minikube
  Normal   Pulled     71s (x5 over 2m30s)  kubelet            spec.containers{python-app}: Container image "public.ecr.aws/docker/library/python:3.11-alpine" already present on machine and can be accessed by the pod
  Normal   Created    70s (x5 over 2m30s)  kubelet            spec.containers{python-app}: Container created
  Normal   Started    70s (x5 over 2m30s)  kubelet            spec.containers{python-app}: Container started
  Warning  BackOff    2s (x5 over 2m28s)   kubelet            spec.containers{python-app}: Back-off restarting failed container python-app in pod fail-1-crashloop-pod_s14-triage(2ca76e66-6c64-4609-a32e-c7dab40cb280)
$ kubectl -n s14-triage logs fail-1-crashloop-pod --previous
[FATAL ERROR]: DATABASE_URL environment variable is MISSING!
```

**Root cause:** the container exits with code 1 a moment after it starts. The log says why: `DATABASE_URL` is not set (`Environment: <none>`). The kubelet restarts it, each time waiting longer (10 s, 20 s, 40 s ... up to 5 min). That waiting state is `CrashLoopBackOff`.

**Fix, step 1:** [fix-step1-env-only.yaml](scenarios/scenario-1-crashloop/fix-step1-env-only.yaml) adds a (fake) `DATABASE_URL`:

```bash
$ kubectl -n s14-triage delete pod fail-1-crashloop-pod && kubectl -n s14-triage apply -f scenario-1-crashloop/fix-step1-env-only.yaml
pod "fail-1-crashloop-pod" deleted from s14-triage namespace
pod/fail-1-crashloop-pod created
$ kubectl -n s14-triage get pod fail-1-crashloop-pod
NAME                   READY   STATUS      RESTARTS      AGE
fail-1-crashloop-pod   0/1     Completed   3 (31s ago)   45s
...
$ kubectl -n s14-triage describe pod fail-1-crashloop-pod | sed -n "/^    State/,/^    Restart Count/p"
    State:          Terminated
      Reason:       Completed
      Exit Code:    0
      Started:      Mon, 12 Oct 2026 01:45:59 +0530
      Finished:     Mon, 12 Oct 2026 01:45:59 +0530
    Last State:     Terminated
      Reason:       Completed
      Exit Code:    0
      Started:      Mon, 12 Oct 2026 01:45:32 +0530
      Finished:     Mon, 12 Oct 2026 01:45:32 +0530
    Ready:          False
    Restart Count:  3
```

The FATAL error is gone (exit code 0 now), but the Pod still restarts. The script prints one line and ends, and a Pod's default `restartPolicy: Always` restarts any container that exits, even successfully. A long-running app must keep running, and a one-off task should be a Job or use `restartPolicy: OnFailure`.

**Fix, step 2 and verify:** [fixed.yaml](scenarios/scenario-1-crashloop/fixed.yaml) sets the variable and keeps the process running (a stand-in for the server loop):

```bash
$ kubectl -n s14-triage delete pod fail-1-crashloop-pod && kubectl -n s14-triage apply -f scenario-1-crashloop/fixed.yaml
pod "fail-1-crashloop-pod" deleted from s14-triage namespace
pod/fail-1-crashloop-pod created
$ kubectl -n s14-triage get pod fail-1-crashloop-pod
NAME                   READY   STATUS    RESTARTS   AGE
fail-1-crashloop-pod   1/1     Running   0          40s
$ kubectl -n s14-triage logs fail-1-crashloop-pod
Application started successfully!
```

### Issue 2: ErrImagePull / ImagePullBackOff (course scenario 2, plus a bug in a course file)

**Identify and investigate**

```bash
$ kubectl -n s14-triage get pod fail-2-imagepull-pod
NAME                   READY   STATUS             RESTARTS   AGE
fail-2-imagepull-pod   0/1     ImagePullBackOff   0          4m3s
$ kubectl -n s14-triage describe pod fail-2-imagepull-pod | sed -n "/^    Image:/p;/^    State/,/^      Reason/p;/^Events/,\$p"
    Image:          public.ecr.aws/docker/library/yatri-api-service:v999-invalid-tag-does-not-exist
    State:          Waiting
      Reason:       ImagePullBackOff
Events:
  Type     Reason     Age                  From               Message
  ----     ------     ----                 ----               -------
  Normal   Scheduled  4m3s                 default-scheduler  Successfully assigned s14-triage/fail-2-imagepull-pod to minikube
  Normal   Pulling    56s (x5 over 4m3s)   kubelet            spec.containers{web-app}: Pulling image "public.ecr.aws/docker/library/yatri-api-service:v999-invalid-tag-does-not-exist"
  Warning  Failed     54s (x5 over 4m2s)   kubelet            spec.containers{web-app}: Failed to pull image "public.ecr.aws/docker/library/yatri-api-service:v999-invalid-tag-does-not-exist": rpc error: code = NotFound desc = failed to pull and unpack image "public.ecr.aws/docker/library/yatri-api-service:v999-invalid-tag-does-not-exist": failed to resolve reference "public.ecr.aws/docker/library/yatri-api-service:v999-invalid-tag-does-not-exist": public.ecr.aws/docker/library/yatri-api-service:v999-invalid-tag-does-not-exist: not found
  Warning  Failed     54s (x5 over 4m2s)   kubelet            spec.containers{web-app}: Error: ErrImagePull
  Normal   BackOff    15s (x14 over 4m1s)  kubelet            spec.containers{web-app}: Back-off pulling image "public.ecr.aws/docker/library/yatri-api-service:v999-invalid-tag-does-not-exist"
  Warning  Failed     15s (x14 over 4m1s)  kubelet            spec.containers{web-app}: Error: ImagePullBackOff
```

`ErrImagePull` is the failed attempt. `ImagePullBackOff` is the waiting between retries (the back-off grows like CrashLoopBackOff's). The events give the exact reason: the registry answered `not found` for `yatri-api-service:v999-invalid-tag-does-not-exist`.

**Root cause:** the image reference points to a repository/tag that was never published. Other common causes give different messages: `401/403 ... unauthorized` (private registry without `imagePullSecrets`), `429 Too Many Requests` (rate limit, as I hit on Docker Hub), `no match for platform` (image without an arm64 build), or DNS/timeout errors (registry not reachable).

**Fix and verify:** [fixed.yaml](scenarios/scenario-2-imagepull/fixed.yaml) uses an image that exists (nginx as a stand-in for the never-published app image):

```bash
$ kubectl -n s14-triage delete pod fail-2-imagepull-pod && kubectl -n s14-triage apply -f scenario-2-imagepull/fixed.yaml
pod "fail-2-imagepull-pod" deleted from s14-triage namespace
pod/fail-2-imagepull-pod created
$ kubectl -n s14-triage wait --for=condition=Ready pod/fail-2-imagepull-pod --timeout=90s && kubectl -n s14-triage get pod fail-2-imagepull-pod
pod/fail-2-imagepull-pod condition met
NAME                   READY   STATUS    RESTARTS   AGE
fail-2-imagepull-pod   1/1     Running   0          1s
```

**Second example:** the course's own `09-service-dns-troubleshooting/dns-test-pod.yaml` has a wrong image name:

```bash
$ kubectl -n s14-service apply -f dns-test-pod.yaml
pod/dns-test created
$ kubectl -n s14-service get pod dns-test
NAME       READY   STATUS             RESTARTS   AGE
dns-test   0/1     ImagePullBackOff   0          15s
$ kubectl -n s14-service describe pod dns-test | grep -E "Failed to pull" | head -1
  Warning  Failed     0s (x2 over 14s)  kubelet            spec.containers{dns-test}: Failed to pull image "registry.k8s.io/e2e-test-images/dnsutils:1.3": rpc error: code = NotFound desc = failed to pull and unpack image "registry.k8s.io/e2e-test-images/dnsutils:1.3": failed to resolve reference "registry.k8s.io/e2e-test-images/dnsutils:1.3": registry.k8s.io/e2e-test-images/dnsutils:1.3: not found
```

The image that exists is `registry.k8s.io/e2e-test-images/jessie-dnsutils:1.3`, the one in the Kubernetes DNS debugging guide. [dns-test-pod-fixed.yaml](02-common-issues/service-connectivity/dns-test-pod-fixed.yaml) uses it:

```bash
$ kubectl -n s14-service delete pod dns-test && kubectl -n s14-service apply -f dns-test-pod-fixed.yaml
pod "dns-test" deleted from s14-service namespace
pod/dns-test created
$ kubectl -n s14-service wait --for=condition=Ready pod/dns-test --timeout=120s && kubectl -n s14-service exec dns-test -- nslookup web-service
pod/dns-test condition met
Server:		10.96.0.10
Address:	10.96.0.10#53

Name:	web-service.s14-service.svc.cluster.local
Address: 10.98.208.220
```

### Issue 3: Pending (course scenario 3 and course 08-pending-pods)

**Identify and investigate**

```bash
$ kubectl -n s14-triage get pod fail-3-pending-pod -o wide
NAME                 READY   STATUS    RESTARTS   AGE     IP       NODE     NOMINATED NODE   READINESS GATES
fail-3-pending-pod   0/1     Pending   0          4m15s   <none>   <none>   <none>           <none>
$ kubectl -n s14-triage describe pod fail-3-pending-pod | sed -n "/^    Requests/,/^      memory/p;/^Conditions/,/^  PodScheduled/p;/^Events/,\$p"
    Requests:
      cpu:        500
      memory:     1000Gi
Conditions:
  Type           Status
  PodScheduled   False 
Events:
  Type     Reason            Age                   From               Message
  ----     ------            ----                  ----               -------
  Warning  FailedScheduling  10s (x11 over 4m15s)  default-scheduler  0/1 nodes are available: 1 Insufficient cpu, 1 Insufficient memory. preemption: 0/1 nodes are available: 1 Preemption is not helpful for scheduling.
$ kubectl get node minikube -o jsonpath='allocatable: cpu={.status.allocatable.cpu} memory={.status.allocatable.memory}{"\n"}'
allocatable: cpu=6 memory=10159960Ki
$ kubectl describe node minikube | sed -n "/^Allocated resources/,/^  memory/p"
Allocated resources:
  (Total limits may be over 100 percent, i.e., overcommitted.)
  Resource           Requests      Limits
  --------           --------      ------
  cpu                1985m (33%)   5650m (94%)
  memory             1986Mi (20%)  3664Mi (36%)
```

**Root cause:** the Pod requests 500 CPUs and 1000Gi of memory. The scheduler only schedules a Pod on a node whose free *allocatable* resources cover the *requests*, and this node has 6 CPUs and about 9.7 GiB in total (`PodScheduled False`, `Insufficient cpu, Insufficient memory`). No node will ever fit it, so it stays Pending (no node, no IP) indefinitely.

**Fix and verify:** [fixed.yaml](scenarios/scenario-3-pending/fixed.yaml) requests `100m` / `64Mi`:

```bash
$ kubectl -n s14-triage delete pod fail-3-pending-pod && kubectl -n s14-triage apply -f scenario-3-pending/fixed.yaml
pod "fail-3-pending-pod" deleted from s14-triage namespace
pod/fail-3-pending-pod created
$ kubectl -n s14-triage wait --for=condition=Ready pod/fail-3-pending-pod --timeout=90s && kubectl -n s14-triage get pod fail-3-pending-pod -o wide
pod/fail-3-pending-pod condition met
NAME                 READY   STATUS    RESTARTS   AGE   IP            NODE       NOMINATED NODE   READINESS GATES
fail-3-pending-pod   1/1     Running   0          4s    10.244.0.67   minikube   <none>           <none>
```

**Second cause, a node selector that matches no node** (course [broken-nodeselector-pod.yaml](02-common-issues/pending/broken-nodeselector-pod.yaml)):

```bash
$ kubectl -n s14-triage apply -f broken-nodeselector-pod.yaml
pod/pending-demo created
$ kubectl -n s14-triage get pod pending-demo
NAME           READY   STATUS    RESTARTS   AGE
pending-demo   0/1     Pending   0          5s
$ kubectl -n s14-triage describe pod pending-demo | sed -n "/^Node-Selectors/p;/^Events/,\$p"
Node-Selectors:              kubernetes.io/hostname=node-that-does-not-exist
Events:
  Type     Reason            Age   From               Message
  ----     ------            ----  ----               -------
  Warning  FailedScheduling  5s    default-scheduler  0/1 nodes are available: 1 node(s) didn't match Pod's node affinity/selector. preemption: 0/1 nodes are available: 1 Preemption is not helpful for scheduling.
$ kubectl get nodes --show-labels | tr "," "\n" | grep -E "NAME|kubernetes.io/hostname"
NAME       STATUS   ROLES           AGE    VERSION   LABELS
kubernetes.io/hostname=minikube
$ kubectl -n s14-triage delete pod pending-demo
pod "pending-demo" deleted from s14-triage namespace
$ kubectl -n s14-triage apply -f fixed-nodeselector-pod.yaml
pod/pending-demo created
$ kubectl -n s14-triage wait --for=condition=Ready pod/pending-demo --timeout=90s && kubectl -n s14-triage get pod pending-demo -o wide
pod/pending-demo condition met
NAME           READY   STATUS    RESTARTS   AGE   IP            NODE       NOMINATED NODE   READINESS GATES
pending-demo   1/1     Running   0          0s    10.244.0.68   minikube   <none>           <none>
$ kubectl -n s14-triage delete pod pending-demo
pod "pending-demo" deleted from s14-triage namespace
```

The message is different (`didn't match Pod's node affinity/selector`): the only node is labelled `kubernetes.io/hostname=minikube`. The course [fixed pod](02-common-issues/pending/fixed-nodeselector-pod.yaml) removes the selector. Other Pending causes have their own messages: taints without tolerations, unbound PVCs, or a full node.

### Issue 4: ContainerCreating that never finishes (missing ConfigMap / Secret volume)

[broken-pod.yaml](02-common-issues/containercreating/broken-pod.yaml) mounts the ConfigMap `report-settings` and the Secret `report-tls`, and neither exists yet.

**Identify and investigate**

```bash
$ kubectl create namespace s14-containercreating
namespace/s14-containercreating created
$ kubectl apply -f broken-pod.yaml
pod/report-app created
$ kubectl -n s14-containercreating get pod report-app
NAME         READY   STATUS              RESTARTS   AGE
report-app   0/1     ContainerCreating   0          51s
$ kubectl -n s14-containercreating describe pod report-app | sed -n "/^Volumes/,/^QoS/p;/^Events/,\$p"
Volumes:
  settings:
    Type:      ConfigMap (a volume populated by a ConfigMap)
    Name:      report-settings
    Optional:  false
  tls:
    Type:        Secret (a volume populated by a Secret)
    SecretName:  report-tls
    Optional:    false
  kube-api-access-bjzpt:
    Type:                    Projected (a volume that contains injected data from multiple sources)
    TokenExpirationSeconds:  3607
    ConfigMapName:           kube-root-ca.crt
    Optional:                false
    DownwardAPI:             true
QoS Class:                   Burstable
Events:
  Type     Reason       Age                From               Message
  ----     ------       ----               ----               -------
  Normal   Scheduled    51s                default-scheduler  Successfully assigned s14-containercreating/report-app to minikube
  Warning  FailedMount  19s (x7 over 50s)  kubelet            MountVolume.SetUp failed for volume "settings" : configmap "report-settings" not found
  Warning  FailedMount  19s (x7 over 50s)  kubelet            MountVolume.SetUp failed for volume "tls" : secret "report-tls" not found
$ kubectl -n s14-containercreating get configmap,secret
NAME                         DATA   AGE
configmap/kube-root-ca.crt   1      51s
```

**Root cause:** the Pod was scheduled, but the kubelet cannot prepare its volumes (`FailedMount ... configmap "report-settings" not found`, the same for the Secret), so the container is never created. There are no logs to read, because nothing has run yet. `describe` / events are the only place the reason shows up. (A missing ConfigMap used as an *env* source gives `CreateContainerConfigError` instead, see Issue 8.)

**Fix and verify:** create the two objects ([missing-objects.yaml](02-common-issues/containercreating/missing-objects.yaml)). The kubelet keeps retrying the mount, so the existing Pod starts by itself:

```bash
$ kubectl apply -f missing-objects.yaml
configmap/report-settings created
secret/report-tls created
$ kubectl -n s14-containercreating get pod report-app
NAME         READY   STATUS    RESTARTS   AGE
report-app   1/1     Running   0          66s
$ kubectl -n s14-containercreating logs report-app
report.format=pdf
report.schedule=daily
tls.crt
tls.key
$ kubectl -n s14-containercreating events --for pod/report-app | tail -4
34s (x7 over 65s)   Warning   FailedMount   Pod/report-app   MountVolume.SetUp failed for volume "tls" : secret "report-tls" not found
1s                  Normal    Pulled        Pod/report-app   Container image "public.ecr.aws/docker/library/busybox:1.36" already present on machine and can be accessed by the pod
1s                  Normal    Created       Pod/report-app   Container created
0s                  Normal    Started       Pod/report-app   Container started
```

### Issue 5: Service connectivity (selector mismatch, then port mismatch)

I used the course `09-service-dns-troubleshooting` files ([deployment.yaml](02-common-issues/service-connectivity/deployment.yaml), [service.yaml](02-common-issues/service-connectivity/service.yaml)) and a small busybox [client](02-common-issues/service-connectivity/client.yaml).

**Identify:** the Pods are Running, the Service exists, but a request through the Service fails:

```bash
$ kubectl create namespace s14-service
namespace/s14-service created
$ kubectl -n s14-service apply -f deployment.yaml -f service.yaml -f client.yaml
deployment.apps/web created
service/web-service created
pod/client created
$ kubectl -n s14-service rollout status deploy/web --timeout=120s && kubectl -n s14-service wait --for=condition=Ready pod/client --timeout=60s
Waiting for deployment "web" rollout to finish: 0 of 2 updated replicas are available...
Waiting for deployment "web" rollout to finish: 1 of 2 updated replicas are available...
deployment "web" successfully rolled out
pod/client condition met
$ kubectl -n s14-service get pods,svc
NAME                       READY   STATUS    RESTARTS   AGE
pod/client                 1/1     Running   0          1s
pod/web-7c797785dc-6lls2   1/1     Running   0          1s
pod/web-7c797785dc-rjf42   1/1     Running   0          1s

NAME                  TYPE        CLUSTER-IP      EXTERNAL-IP   PORT(S)   AGE
service/web-service   ClusterIP   10.98.208.220   <none>        80/TCP    1s
$ kubectl -n s14-service exec client -- wget -T 3 -qO- http://web-service
wget: can't connect to remote host (10.98.208.220): Connection refused
command terminated with exit code 1
```

**Investigate**

```bash
$ kubectl -n s14-service get endpointslices -l kubernetes.io/service-name=web-service
NAME                ADDRESSTYPE   PORTS     ENDPOINTS   AGE
web-service-zp2kb   IPv4          <unset>   <unset>     2s
$ kubectl -n s14-service describe service web-service | grep -E "^(Selector|Port|TargetPort|Endpoints)"
Selector:                 app=web-ahsgdf
Port:                     <unset>  80/TCP
TargetPort:               80/TCP
Endpoints:                
$ kubectl -n s14-service get pods --show-labels
NAME                   READY   STATUS    RESTARTS   AGE   LABELS
client                 1/1     Running   0          2s    <none>
web-7c797785dc-6lls2   1/1     Running   0          2s    app=web,pod-template-hash=7c797785dc
web-7c797785dc-rjf42   1/1     Running   0          2s    app=web,pod-template-hash=7c797785dc
$ kubectl -n s14-service get pods -l app=web-ahsgdf
No resources found in s14-service namespace.
```

**Root cause:** the course `service.yaml` has `selector: app: web-ahsgdf` (a typo), but the Pods are labelled `app=web`. No Pod matches, so the EndpointSlice is empty, and kube-proxy rejects connections to the ClusterIP (`Connection refused`). Everything else is healthy, which is why this is easy to miss. (The course also has `broken-service.yaml` with `app: does-not-exist`, the same problem on purpose.)

**Fix and verify:** [service-fixed.yaml](02-common-issues/service-connectivity/service-fixed.yaml) with `selector: app: web`:

```bash
$ kubectl -n s14-service apply -f service-fixed.yaml
service/web-service configured
$ kubectl -n s14-service get endpointslices -l kubernetes.io/service-name=web-service
NAME                ADDRESSTYPE   PORTS   ENDPOINTS                 AGE
web-service-zp2kb   IPv4          80      10.244.0.76,10.244.0.77   5s
$ kubectl -n s14-service exec client -- sh -c "wget -T 3 -qO- http://web-service | grep -i \"<title>\""
<title>Welcome to nginx!</title>
```

**Second Service problem: wrong `targetPort`** ([service-wrong-port.yaml](02-common-issues/service-connectivity/service-wrong-port.yaml), `targetPort: 8080`):

```bash
$ kubectl -n s14-service apply -f service-wrong-port.yaml
service/web-service configured
$ kubectl -n s14-service exec client -- wget -T 3 -qO- http://web-service
wget: can't connect to remote host (10.98.208.220): Connection refused
command terminated with exit code 1
$ kubectl -n s14-service get endpointslices -l kubernetes.io/service-name=web-service
NAME                ADDRESSTYPE   PORTS   ENDPOINTS                 AGE
web-service-zp2kb   IPv4          8080    10.244.0.77,10.244.0.76   17s
$ kubectl -n s14-service describe service web-service | grep -E "^(Selector|TargetPort|Endpoints)"
Selector:                 app=web
TargetPort:               8080/TCP
Endpoints:                10.244.0.77:8080,10.244.0.76:8080
$ kubectl -n s14-service get pods -l app=web -o jsonpath='{.items[0].spec.containers[0].ports}{"\n"}'
[{"containerPort":80,"protocol":"TCP"}]
$ POD_IP=$(kubectl -n s14-service get pods -l app=web -o jsonpath="{.items[0].status.podIP}"); kubectl -n s14-service exec client -- sh -c "wget -T 3 -qO- http://$POD_IP:8080 >/dev/null 2>&1 && echo 8080 OK || echo 8080 refused; wget -T 3 -qO- http://$POD_IP:80 >/dev/null && echo 80 OK"
8080 refused
80 OK
```

Now the endpoints exist, but on port 8080, where nothing listens (the container port is 80). Testing the Pod IP directly shows that port 80 works and 8080 is refused. **Fix and verify:** set `targetPort: 80` again:

```bash
$ kubectl -n s14-service apply -f service-fixed.yaml
service/web-service configured
$ kubectl -n s14-service get endpointslices -l kubernetes.io/service-name=web-service
NAME                ADDRESSTYPE   PORTS   ENDPOINTS                 AGE
web-service-zp2kb   IPv4          80      10.244.0.76,10.244.0.77   21s
$ kubectl -n s14-service exec client -- sh -c "wget -T 3 -qO- http://web-service | grep -i \"<title>\""
<title>Welcome to nginx!</title>
```

### Issue 6: DNS (course scenario 4)

**Identify:** `fail-4-dns-failure-pod` looks perfectly healthy, and its log shows no error because the script uses `curl -s ... || true`. Running the same request myself shows the real error:

```bash
$ kubectl -n s14-triage get pod fail-4-dns-failure-pod
NAME                     READY   STATUS    RESTARTS   AGE
fail-4-dns-failure-pod   1/1     Running   0          4m46s
$ kubectl -n s14-triage logs fail-4-dns-failure-pod
Attempting connection to internal database...
Process sleeping...
$ kubectl -n s14-triage exec fail-4-dns-failure-pod -- curl -sS --connect-timeout 3 http://postgres-db-wrong-name.production.svc.cluster.local:5432; echo "exit code: $?"
curl: (6) Could not resolve host: postgres-db-wrong-name.production.svc.cluster.local
command terminated with exit code 6
exit code: 6
```

**Investigate** with the DNS test Pod (from Issue 2) in the same namespace:

```bash
$ kubectl -n s14-triage get pod dns-test
NAME       READY   STATUS    RESTARTS   AGE
dns-test   1/1     Running   0          1s
$ kubectl -n s14-triage exec dns-test -- nslookup postgres-db-wrong-name.production.svc.cluster.local
Server:		10.96.0.10
Address:	10.96.0.10#53

** server can't find postgres-db-wrong-name.production.svc.cluster.local: NXDOMAIN

command terminated with exit code 1
$ kubectl -n s14-triage exec dns-test -- nslookup kubernetes.default
Server:		10.96.0.10
Address:	10.96.0.10#53

Name:	kubernetes.default.svc.cluster.local
Address: 10.96.0.1

$ kubectl -n s14-triage exec dns-test -- cat /etc/resolv.conf
search s14-triage.svc.cluster.local svc.cluster.local cluster.local
nameserver 10.96.0.10
options ndots:5
$ kubectl -n kube-system get pods -l k8s-app=kube-dns; kubectl -n kube-system get svc kube-dns
NAME                       READY   STATUS    RESTARTS   AGE
coredns-559f6c778d-mb9q4   1/1     Running   0          4d2h
NAME       TYPE        CLUSTER-IP   EXTERNAL-IP   PORT(S)                  AGE
kube-dns   ClusterIP   10.96.0.10   <none>        53/UDP,53/TCP,9153/TCP   4d2h
...
$ kubectl get namespace production
Error from server (NotFound): namespaces "production" not found
...
$ kubectl -n kube-system logs -l k8s-app=kube-dns --tail=-1 --since=15m | grep "postgres-db-wrong-name" | head -2
[INFO] 10.244.0.55:52365 - 1052 "AAAA IN postgres-db-wrong-name.production.svc.cluster.local.s14-triage.svc.cluster.local. udp 98 false 512" NXDOMAIN qr,aa,rd 191 0.000804509s
[INFO] 10.244.0.55:36679 - 58221 "AAAA IN postgres-db-wrong-name.production.svc.cluster.local.svc.cluster.local. udp 87 false 512" NXDOMAIN qr,aa,rd 180 0.000197189s
$ kubectl get svc -A --field-selector metadata.name=postgres-db-wrong-name
No resources found
```

What this shows:

- DNS itself works: CoreDNS is Running, `/etc/resolv.conf` points to the `kube-dns` Service (10.96.0.10), and `kubernetes.default` resolves.
- Only this one name fails with `NXDOMAIN`. The name has the form `<service>.<namespace>.svc.cluster.local`, but there is no namespace `production` and no Service `postgres-db-wrong-name`.
- The CoreDNS log shows the search-path expansion. With `ndots:5`, a name with fewer than five dots is first tried with each search suffix (`...cluster.local.s14-triage.svc.cluster.local`, `...cluster.local.svc.cluster.local`), and every attempt is NXDOMAIN.

**Root cause:** wrong host name (wrong Service name and a namespace that does not exist). The database the client should talk to did not exist either.

**Fix and verify:** deploy the database as Service `postgres-db` in `s14-triage` ([postgres-db.yaml](scenarios/scenario-4-dns-failure/postgres-db.yaml)) and use its real name in [fixed.yaml](scenarios/scenario-4-dns-failure/fixed.yaml):

```bash
$ kubectl -n s14-triage apply -f scenario-4-dns-failure/postgres-db.yaml
deployment.apps/postgres-db created
service/postgres-db created
$ kubectl -n s14-triage rollout status deploy/postgres-db --timeout=120s
Waiting for deployment "postgres-db" rollout to finish: 0 of 1 updated replicas are available...
deployment "postgres-db" successfully rolled out
$ kubectl -n s14-triage exec dns-test -- nslookup postgres-db.s14-triage.svc.cluster.local
Server:		10.96.0.10
Address:	10.96.0.10#53

Name:	postgres-db.s14-triage.svc.cluster.local
Address: 10.106.194.116

$ kubectl -n s14-triage delete pod fail-4-dns-failure-pod && kubectl -n s14-triage apply -f scenario-4-dns-failure/fixed.yaml
pod "fail-4-dns-failure-pod" deleted from s14-triage namespace
pod/fail-4-dns-failure-pod created
$ kubectl -n s14-triage get pod fail-4-dns-failure-pod
NAME                     READY   STATUS    RESTARTS   AGE
fail-4-dns-failure-pod   1/1     Running   0          15s
$ kubectl -n s14-triage logs fail-4-dns-failure-pod
Attempting connection to internal database...
curl exit code: 52
Process sleeping...
$ kubectl -n s14-triage logs deploy/postgres-db --tail=1
2026-10-11 20:18:20.923 UTC [58] LOG:  invalid length of startup packet
```

curl's exit code changed from 6 ("Could not resolve host") to 52 ("Empty reply from server"). The name now resolves and the TCP connection is made. Postgres does not speak HTTP, so it closes the connection, and its log shows the client's bytes arriving (`invalid length of startup packet`). A real client would use a Postgres driver. For DNS problems that affect *every* name, the next places to look are the CoreDNS Pods, their logs and the `coredns` ConfigMap. I did not break those, because CoreDNS is shared by everyone on this cluster.

### Issue 7: Pod networking blocked by a NetworkPolicy

**Does this cluster enforce NetworkPolicy?** The brief warns that minikube's default CNI may not. I tested it instead of assuming: a `web` Deployment and two client Pods, `frontend` (`role=frontend`) and `intruder` (`role=other`), in [app.yaml](02-common-issues/network-policy/app.yaml).

```bash
$ kubectl create namespace s14-netpol
namespace/s14-netpol created
$ kubectl apply -f app.yaml
deployment.apps/web created
service/web created
pod/frontend created
pod/intruder created
$ kubectl -n s14-netpol rollout status deploy/web --timeout=120s && kubectl -n s14-netpol wait --for=condition=Ready pod/frontend pod/intruder --timeout=60s
Waiting for deployment "web" rollout to finish: 0 of 1 updated replicas are available...
deployment "web" successfully rolled out
pod/frontend condition met
pod/intruder condition met
$ for p in frontend intruder; do echo -n "$p -> web: "; kubectl -n s14-netpol exec $p -- sh -c "wget -T 3 -qO- http://web >/dev/null 2>&1 && echo OK || echo FAILED"; done
frontend -> web: OK
intruder -> web: OK
```

Then someone applies a default-deny policy ([default-deny-ingress.yaml](02-common-issues/network-policy/default-deny-ingress.yaml)):

```bash
$ kubectl apply -f default-deny-ingress.yaml
networkpolicy.networking.k8s.io/default-deny-ingress created
$ for p in frontend intruder; do echo -n "$p -> web: "; kubectl -n s14-netpol exec $p -- sh -c "wget -T 3 -qO- http://web >/dev/null 2>&1 && echo OK || echo FAILED"; done
frontend -> web: FAILED
intruder -> web: FAILED
```

**Investigate:** rule out the other layers one by one:

```bash
$ kubectl -n s14-netpol exec frontend -- wget -T 3 -qO- http://web
wget: download timed out
command terminated with exit code 1
...
$ kubectl -n s14-netpol exec frontend -- nslookup web.s14-netpol.svc.cluster.local
Server:		10.96.0.10
Address:	10.96.0.10:53


Name:	web.s14-netpol.svc.cluster.local
Address: 10.111.185.154
...
$ kubectl -n s14-netpol get endpointslices -l kubernetes.io/service-name=web
NAME        ADDRESSTYPE   PORTS   ENDPOINTS     AGE
web-ct52j   IPv4          80      10.244.0.82   25s
$ kubectl -n s14-netpol exec deploy/web -- curl -s -o /dev/null -w "local check inside the web pod: HTTP %{http_code}\n" localhost
local check inside the web pod: HTTP 200
$ kubectl -n s14-netpol get networkpolicy
NAME                   POD-SELECTOR   AGE
default-deny-ingress   <none>         23s
$ kubectl -n s14-netpol describe networkpolicy default-deny-ingress | sed -n "/^Spec/,\$p"
Spec:
  PodSelector:     <none> (Allowing the specific traffic to all pods in this namespace)
  Allowing ingress traffic:
    <none> (Selected pods are isolated for ingress connectivity)
  Not affecting egress traffic
  Policy Types: Ingress
$ kubectl -n kube-system get ds kindnet -o jsonpath='{.spec.template.spec.containers[0].image}{"\n"}'
docker.io/kindest/kindnetd:v20260820-69b56db7
```

- The request **times out** instead of being refused. Packets are dropped silently, which is typical for a firewall or policy and different from Issue 5's `Connection refused`.
- DNS resolves, the EndpointSlice has the Pod, and the app answers inside its own Pod, so the Service, DNS and app are fine.
- `kubectl get networkpolicy` shows a policy selecting every Pod (`<none>` = all) with no allowed ingress.
- The CNI is kindnet (`kindest/kindnetd:v20260820`). Newer kindnet versions include a NetworkPolicy implementation, and the blocked traffic proves it is enforced on this cluster. On a CNI without NetworkPolicy support (for example plain bridge or older flannel), the same policy would be stored but have no effect.

**Root cause:** default-deny ingress for the namespace with no rule allowing the frontend.

**Fix and verify:** keep the default deny and allow only `role=frontend` -> `app=web` on TCP 80 ([allow-frontend-to-web.yaml](02-common-issues/network-policy/allow-frontend-to-web.yaml)):

```bash
$ kubectl apply -f allow-frontend-to-web.yaml
networkpolicy.networking.k8s.io/allow-frontend-to-web created
$ for p in frontend intruder; do echo -n "$p -> web: "; kubectl -n s14-netpol exec $p -- sh -c "wget -T 3 -qO- http://web >/dev/null 2>&1 && echo OK || echo FAILED"; done
frontend -> web: OK
intruder -> web: FAILED
$ kubectl -n s14-netpol get networkpolicy
NAME                    POD-SELECTOR   AGE
allow-frontend-to-web   app=web        8s
default-deny-ingress    <none>         31s
```

The frontend gets through again, and the unrelated Pod is still blocked, which is what the policy was for.

### Issue 8: Configuration issue (env var reads a ConfigMap key that does not exist)

[configmap.yaml](02-common-issues/configuration/configmap.yaml) defines `DATABASE_HOST`, but [deployment-broken.yaml](02-common-issues/configuration/deployment-broken.yaml) reads key `DB_HOST`.

**Identify and investigate**

```bash
$ kubectl create namespace s14-config
namespace/s14-config created
$ kubectl apply -f configmap.yaml -f deployment-broken.yaml
configmap/orders-config created
deployment.apps/orders-api created
$ kubectl -n s14-config get pods
NAME                          READY   STATUS                       RESTARTS   AGE
orders-api-58bc96d5b7-vch4z   0/1     CreateContainerConfigError   0          21s
$ kubectl -n s14-config describe pod -l app=orders-api | sed -n "/^    State/,/^      Reason/p;/^    Environment/,/^    Mounts/p;/^Events/,\$p"
    State:          Waiting
      Reason:       CreateContainerConfigError
    Environment:
      DB_HOST:    <set to the key 'DB_HOST' of config map 'orders-config'>        Optional: false
      DB_PORT:    <set to the key 'DATABASE_PORT' of config map 'orders-config'>  Optional: false
      LOG_LEVEL:  <set to the key 'LOG_LEVEL' of config map 'orders-config'>      Optional: false
    Mounts:
Events:
  Type     Reason     Age               From               Message
  ----     ------     ----              ----               -------
  Normal   Scheduled  21s               default-scheduler  Successfully assigned s14-config/orders-api-58bc96d5b7-vch4z to minikube
  Normal   Pulled     6s (x3 over 19s)  kubelet            spec.containers{api}: Container image "public.ecr.aws/docker/library/busybox:1.36" already present on machine and can be accessed by the pod
  Warning  Failed     6s (x3 over 19s)  kubelet            spec.containers{api}: Error: couldn't find key DB_HOST in ConfigMap s14-config/orders-config
$ kubectl -n s14-config get configmap orders-config -o jsonpath="{.data}{\"\n\"}"
{"DATABASE_HOST":"postgres.s14-config.svc.cluster.local","DATABASE_PORT":"5432","LOG_LEVEL":"info"}
$ kubectl -n s14-config logs deploy/orders-api
Error from server (BadRequest): container "api" in pod "orders-api-58bc96d5b7-vch4z" is waiting to start: CreateContainerConfigError
```

**Root cause:** `couldn't find key DB_HOST in ConfigMap s14-config/orders-config`. The kubelet cannot build the container's environment, so it never starts the container (`CreateContainerConfigError`, no logs). The ConfigMap's real keys are `DATABASE_HOST`, `DATABASE_PORT`, `LOG_LEVEL`.

**Fix and verify:** [deployment-fixed.yaml](02-common-issues/configuration/deployment-fixed.yaml) reads the right key:

```bash
$ diff deployment-broken.yaml deployment-fixed.yaml
1c1
< # BUG: the Deployment asks for key DB_HOST, but the ConfigMap key is DATABASE_HOST.
---
> # FIXED: the env var DB_HOST now reads the key that really exists (DATABASE_HOST).
26c26
<                   key: DB_HOST
---
>                   key: DATABASE_HOST
$ kubectl apply -f deployment-fixed.yaml
deployment.apps/orders-api configured
$ kubectl -n s14-config rollout status deploy/orders-api --timeout=120s
Waiting for deployment "orders-api" rollout to finish: 1 old replicas are pending termination...
Waiting for deployment "orders-api" rollout to finish: 1 old replicas are pending termination...
Waiting for deployment "orders-api" rollout to finish: 1 old replicas are pending termination...
deployment "orders-api" successfully rolled out
$ kubectl -n s14-config get pods
NAME                          READY   STATUS        RESTARTS   AGE
orders-api-58bc96d5b7-vch4z   0/1     Terminating   0          22s
orders-api-699467d74-hws9h    1/1     Running       0          1s
$ kubectl -n s14-config logs deploy/orders-api
Found 2 pods, using pod/orders-api-699467d74-hws9h
orders-api starting, db=postgres.s14-config.svc.cluster.local:5432 log=info
```

(The other option is to rename the key in the ConfigMap, if other apps don't depend on it. `optional: true` on the reference would hide the problem, not fix it.)

### Issue 9 (bonus): OOMKilled (course scenario 5)

```bash
$ kubectl -n s14-triage get pod fail-5-oomkilled-pod
NAME                   READY   STATUS      RESTARTS       AGE
fail-5-oomkilled-pod   0/1     OOMKilled   6 (3m7s ago)   5m54s
$ kubectl -n s14-triage describe pod fail-5-oomkilled-pod | sed -n "/^    Last State/,/^    Restart Count/p;/^    Limits/,/^      memory/p"
    Last State:     Terminated
      Reason:       OOMKilled
      Exit Code:    137
      Started:      Mon, 12 Oct 2026 01:45:34 +0530
      Finished:     Mon, 12 Oct 2026 01:45:34 +0530
    Ready:          False
    Restart Count:  6
    Limits:
      memory:  20Mi
...
$ kubectl -n s14-triage get events --field-selector involvedObject.name=fail-5-oomkilled-pod --sort-by=.lastTimestamp | tail -3
19s         Normal    Created     pod/fail-5-oomkilled-pod   Container created
19s         Normal    Started     pod/fail-5-oomkilled-pod   Container started
18s         Warning   BackOff     pod/fail-5-oomkilled-pod   Back-off restarting failed container memory-leaker in pod fail-5-oomkilled-pod_s14-triage(7f2e1d64-8e9d-4202-8395-0b71d7d67ba4)
```

**Root cause:** `Reason: OOMKilled`, `Exit Code: 137` (128 + SIGKILL). The kernel killed the process when it went over its 20Mi memory limit. The code keeps 100 chunks of 10 MiB in a list, about 1000 MiB, although the course comment says 200MB. Raising the limit above 1 GiB on a shared node would only hide the leak, so [fixed.yaml](scenarios/scenario-5-oomkilled/fixed.yaml) processes one chunk at a time and frees it, with a 64Mi limit. It is a batch task, so it also uses `restartPolicy: OnFailure`.

```bash
$ kubectl -n s14-triage delete pod fail-5-oomkilled-pod && kubectl -n s14-triage apply -f scenario-5-oomkilled/fixed.yaml
pod "fail-5-oomkilled-pod" deleted from s14-triage namespace
pod/fail-5-oomkilled-pod created
$ kubectl -n s14-triage get pod fail-5-oomkilled-pod
NAME                   READY   STATUS      RESTARTS   AGE
fail-5-oomkilled-pod   0/1     Completed   0          20s
$ kubectl -n s14-triage logs fail-5-oomkilled-pod
Processing 100 chunks of 10 MiB, one at a time...
done, processed 1000 MiB
$ kubectl -n s14-triage get pod fail-5-oomkilled-pod -o jsonpath='{.status.containerStatuses[0].state.terminated.reason} exit={.status.containerStatuses[0].state.terminated.exitCode} restarts={.status.containerStatuses[0].restartCount}{"\n"}'
Completed exit=0 restarts=0
```

### All triage scenarios after the fixes

```bash
$ kubectl -n s14-triage get pods -l tier=triage-gauntlet
NAME                     READY   STATUS      RESTARTS   AGE
fail-1-crashloop-pod     1/1     Running     0          2m59s
fail-2-imagepull-pod     1/1     Running     0          2m11s
fail-3-pending-pod       1/1     Running     0          2m1s
fail-4-dns-failure-pod   1/1     Running     0          44s
fail-5-oomkilled-pod     0/1     Completed   0          21s
```

| # | Issue | First signal | Command that showed the cause | Root cause | Fix |
| :--- | :--- | :--- | :--- | :--- | :--- |
| 1 | CrashLoopBackOff | `CrashLoopBackOff`, restarts | `logs --previous` | missing `DATABASE_URL`, then a process that exits | set env, keep the process running |
| 2 | ErrImagePull / ImagePullBackOff | `ErrImagePull` | `describe` events | repository/tag `not found` | correct image reference |
| 3 | Pending | `Pending`, no node | `describe` events (`FailedScheduling`) | requests larger than the node / selector matching no node | realistic requests / remove selector |
| 4 | ContainerCreating | stuck `ContainerCreating` | `describe` events (`FailedMount`) | ConfigMap and Secret volume sources missing | create them |
| 5 | Service connectivity | `Connection refused` on the ClusterIP | `get endpointslices`, `--show-labels` | selector typo / wrong `targetPort` | fix selector / port |
| 6 | DNS | `curl: (6) Could not resolve host` | `nslookup` from a test Pod, CoreDNS log | wrong service name and namespace | create the service, use `<svc>.<ns>.svc.cluster.local` |
| 7 | Pod networking | `download timed out` | `get networkpolicy` after ruling out DNS/endpoints/app | default-deny ingress | add an allow rule for the frontend |
| 8 | Configuration | `CreateContainerConfigError` | `describe` events | env references a missing ConfigMap key | reference the right key |
| 9 | OOMKilled | `OOMKilled`, exit 137 | `describe` (Last State) | memory leak vs 20Mi limit | fix the leak, OnFailure |

## Task 3: Mini project (Kubernetes troubleshooting challenge)

Course instructions: [03-mini-project/COURSE-INSTRUCTIONS.md](03-mini-project/COURSE-INSTRUCTIONS.md). Files: the course `deployment.yaml` (2 nginx replicas, `app: troubleshooting-app`), `service.yaml` and `broken-pod.yaml`, in namespace `s14-mini`.

### 1-4. Deploy and check the application, the Service and its endpoints

```bash
$ kubectl create namespace s14-mini
namespace/s14-mini created
$ kubectl -n s14-mini apply -f deployment.yaml && kubectl -n s14-mini apply -f service.yaml
deployment.apps/troubleshooting-app created
service/troubleshooting-service created
$ kubectl -n s14-mini rollout status deploy/troubleshooting-app --timeout=120s
Waiting for deployment "troubleshooting-app" rollout to finish: 0 of 2 updated replicas are available...
Waiting for deployment "troubleshooting-app" rollout to finish: 1 of 2 updated replicas are available...
deployment "troubleshooting-app" successfully rolled out
$ kubectl -n s14-mini get pods; kubectl -n s14-mini get service
NAME                                   READY   STATUS    RESTARTS   AGE
troubleshooting-app-5696447488-czls6   1/1     Running   0          1s
troubleshooting-app-5696447488-t7b4x   1/1     Running   0          1s
NAME                      TYPE        CLUSTER-IP      EXTERNAL-IP   PORT(S)   AGE
troubleshooting-service   ClusterIP   10.104.160.83   <none>        80/TCP    1s
$ kubectl -n s14-mini get pods -o wide
NAME                                   READY   STATUS    RESTARTS   AGE   IP            NODE       NOMINATED NODE   READINESS GATES
troubleshooting-app-5696447488-czls6   1/1     Running   0          1s    10.244.0.86   minikube   <none>           <none>
troubleshooting-app-5696447488-t7b4x   1/1     Running   0          1s    10.244.0.87   minikube   <none>           <none>
$ POD=$(kubectl -n s14-mini get pods -l app=troubleshooting-app -o jsonpath="{.items[0].metadata.name}"); kubectl -n s14-mini describe pod $POD | sed -n "/^Name:/p;/^Status:/p;/^    Image:/p;/^    State/,/^    Ready/p;/^Events/,\$p"
Name:             troubleshooting-app-5696447488-czls6
Status:           Running
    Image:          public.ecr.aws/docker/library/nginx:1.27
    State:          Running
      Started:      Mon, 12 Oct 2026 01:52:21 +0530
    Ready:          True
Events:
  Type    Reason     Age   From               Message
  ----    ------     ----  ----               -------
  Normal  Scheduled  1s    default-scheduler  Successfully assigned s14-mini/troubleshooting-app-5696447488-czls6 to minikube
  Normal  Pulled     1s    kubelet            spec.containers{app}: Container image "public.ecr.aws/docker/library/nginx:1.27" already present on machine and can be accessed by the pod
  Normal  Created    1s    kubelet            spec.containers{app}: Container created
  Normal  Started    1s    kubelet            spec.containers{app}: Container started
$ kubectl -n s14-mini logs deploy/troubleshooting-app --tail=5
Found 2 pods, using pod/troubleshooting-app-5696447488-czls6
2026/10/11 20:22:21 [notice] 1#1: start worker process 30
2026/10/11 20:22:21 [notice] 1#1: start worker process 31
2026/10/11 20:22:21 [notice] 1#1: start worker process 32
2026/10/11 20:22:21 [notice] 1#1: start worker process 33
2026/10/11 20:22:21 [notice] 1#1: start worker process 34
$ kubectl -n s14-mini exec deploy/troubleshooting-app -- curl -s localhost | grep -i "<title>"
<title>Welcome to nginx!</title>
$ kubectl -n s14-mini describe service troubleshooting-service | grep -E "^(Selector|Port|TargetPort|Endpoints)"
Selector:                 app=troubleshooting-app
Port:                     <unset>  80/TCP
TargetPort:               80/TCP
Endpoints:                10.244.0.86:80,10.244.0.87:80
$ kubectl -n s14-mini get endpoints troubleshooting-service
Warning: v1 Endpoints is deprecated in v1.33+; use discovery.k8s.io/v1 EndpointSlice
NAME                      ENDPOINTS                       AGE
troubleshooting-service   10.244.0.86:80,10.244.0.87:80   1s
```

The Pods are Running and Ready, nginx answers on localhost inside the container, and the Service selector `app=troubleshooting-app` matches both Pods (two endpoints on port 80).

### 5-7. The broken Pod

```bash
$ kubectl -n s14-mini apply -f broken-pod.yaml
pod/project-broken-pod created
$ kubectl -n s14-mini get pod project-broken-pod
NAME                 READY   STATUS             RESTARTS   AGE
project-broken-pod   0/1     ImagePullBackOff   0          20s
$ kubectl -n s14-mini describe pod project-broken-pod | sed -n "/^    Image:/p;/^    State/,/^      Reason/p;/^Events/,\$p"
    Image:          public.ecr.aws/docker/library/nginx:this-tag-does-not-exist
    State:          Waiting
      Reason:       ImagePullBackOff
Events:
  Type     Reason     Age               From               Message
  ----     ------     ----              ----               -------
  Normal   Scheduled  20s               default-scheduler  Successfully assigned s14-mini/project-broken-pod to minikube
  Normal   BackOff    18s               kubelet            spec.containers{app}: Back-off pulling image "public.ecr.aws/docker/library/nginx:this-tag-does-not-exist"
  Warning  Failed     18s               kubelet            spec.containers{app}: Error: ImagePullBackOff
  Normal   Pulling    7s (x2 over 20s)  kubelet            spec.containers{app}: Pulling image "public.ecr.aws/docker/library/nginx:this-tag-does-not-exist"
  Warning  Failed     6s (x2 over 19s)  kubelet            spec.containers{app}: Failed to pull image "public.ecr.aws/docker/library/nginx:this-tag-does-not-exist": rpc error: code = NotFound desc = failed to pull and unpack image "public.ecr.aws/docker/library/nginx:this-tag-does-not-exist": failed to resolve reference "public.ecr.aws/docker/library/nginx:this-tag-does-not-exist": public.ecr.aws/docker/library/nginx:this-tag-does-not-exist: not found
  Warning  Failed     6s (x2 over 19s)  kubelet            spec.containers{app}: Error: ErrImagePull
```

Answers:

1. **What is the Pod status?** `ImagePullBackOff` (the first attempts showed `ErrImagePull`). `READY 0/1`, 0 restarts, because the container was never created.
2. **What is the actual error?** `Failed to pull image "public.ecr.aws/docker/library/nginx:this-tag-does-not-exist": ... not found`.
3. **Which command helped you find the reason?** `kubectl describe pod project-broken-pod`, in the Events section. `kubectl get` only shows the status, and `kubectl logs` has nothing because no container ever ran.
4. **What is wrong with the image?** The repository (nginx) is fine, but the tag `this-tag-does-not-exist` was never published.
5. **How would you fix it?** Use a tag that exists, preferably a pinned version like `nginx:1.27`. A Pod's image can be changed in place, but the simple way is to delete and recreate it:

```bash
$ kubectl -n s14-mini delete pod project-broken-pod && kubectl -n s14-mini run project-broken-pod --image=public.ecr.aws/docker/library/nginx:1.27
pod "project-broken-pod" deleted from s14-mini namespace
pod/project-broken-pod created
$ kubectl -n s14-mini wait --for=condition=Ready pod/project-broken-pod --timeout=90s && kubectl -n s14-mini get pod project-broken-pod
pod/project-broken-pod condition met
NAME                 READY   STATUS    RESTARTS   AGE
project-broken-pod   1/1     Running   0          0s
```

### 8-9. Service selector challenge

```bash
$ diff service.yaml service-wrong-selector.yaml; kubectl -n s14-mini apply -f service-wrong-selector.yaml
1,2c1
< # Copied unchanged from the course repo session-14-kubernetes-troubleshooting/mini-project/service.yaml.
< # Namespace given with -n s14-mini.
---
> # Mini-project step 8: service.yaml with the selector changed to app: wrong-app on purpose.
11c10
<     app: troubleshooting-app
---
>     app: wrong-app
service/troubleshooting-service configured
$ kubectl -n s14-mini get service
NAME                      TYPE        CLUSTER-IP      EXTERNAL-IP   PORT(S)   AGE
troubleshooting-service   ClusterIP   10.104.160.83   <none>        80/TCP    35s
$ kubectl -n s14-mini get endpoints troubleshooting-service
Warning: v1 Endpoints is deprecated in v1.33+; use discovery.k8s.io/v1 EndpointSlice
NAME                      ENDPOINTS   AGE
troubleshooting-service   <none>      36s
$ kubectl -n s14-mini exec project-broken-pod -- curl -s -m 3 http://troubleshooting-service; echo "curl exit code: $?"
command terminated with exit code 7
curl exit code: 7
$ kubectl -n s14-mini get pods --show-labels
NAME                                   READY   STATUS    RESTARTS   AGE   LABELS
project-broken-pod                     1/1     Running   0          4s    run=project-broken-pod
troubleshooting-app-5696447488-czls6   1/1     Running   0          36s   app=troubleshooting-app,pod-template-hash=5696447488
troubleshooting-app-5696447488-t7b4x   1/1     Running   0          36s   app=troubleshooting-app,pod-template-hash=5696447488
$ kubectl -n s14-mini describe service troubleshooting-service | grep -E "^(Selector|Endpoints)"
Selector:                 app=wrong-app
Endpoints:                
```

Pods carry `app=troubleshooting-app`, and the Service now selects `app=wrong-app`, so it has no endpoints and `curl` fails with exit code 7 (could not connect). Restoring the selector fixes it:

```bash
$ kubectl -n s14-mini apply -f service.yaml
service/troubleshooting-service configured
$ kubectl -n s14-mini get endpoints troubleshooting-service
Warning: v1 Endpoints is deprecated in v1.33+; use discovery.k8s.io/v1 EndpointSlice
NAME                      ENDPOINTS                       AGE
troubleshooting-service   10.244.0.86:80,10.244.0.87:80   39s
$ kubectl -n s14-mini exec project-broken-pod -- curl -s -m 3 http://troubleshooting-service | grep -i "<title>"
<title>Welcome to nginx!</title>
```

### 11. Troubleshooting table

| Problem | What I saw | Command I used | Root cause | Fix |
| :--- | :--- | :--- | :--- | :--- |
| **Broken Pod** | `project-broken-pod 0/1 ImagePullBackOff` | `kubectl get pod`, `kubectl describe pod` | image tag `this-tag-does-not-exist` does not exist | recreate with `nginx:1.27` |
| **Service Problem** | `troubleshooting-service` endpoints `<none>`, curl exit 7 | `kubectl get endpoints`, `kubectl get pods --show-labels`, `kubectl describe service` | selector `app=wrong-app` matches no Pod | selector back to `app=troubleshooting-app` |
| **Image Problem** | `Failed to pull image ... not found` in events | `kubectl describe pod` (Events) | wrong image reference (also seen in course scenario 2 and the course `dns-test` Pod) | point to an image/tag that exists in a reachable registry |

### 12. README questions

1. **What does `kubectl get` tell us?** The current state of resources at a glance: whether Pods are Running, how many containers are Ready, how often they restarted, and how old they are. It tells you *what* is happening, not *why*.
2. **What is the difference between `get` and `describe`?** `get` is a one-line summary per object. `describe` is the detailed view of one object: spec (image, ports, env, mounts, probes), state and last state with exit codes, conditions, and the recent events where most causes appear.
3. **Why do we use `kubectl logs`?** To read what the application wrote to stdout/stderr, for example error messages, stack traces and missing config. `--previous` shows the output of the last crashed container, which is essential for CrashLoopBackOff.
4. **When would you use `kubectl exec`?** When the container is running and I need to test from inside: call the app on `localhost`, check env vars and mounted files, look at `/etc/resolv.conf`, run `nslookup` / `wget` to other Services. It does not help when the container keeps crashing or never started.
5. **What does `CrashLoopBackOff` mean?** The container starts, exits, and is restarted again and again, with growing waits in between (up to 5 minutes). It is a symptom. The cause is in `logs --previous` and in the exit code / reason in `describe`: an app error, missing config, a bad command, a failing liveness probe, or OOM.
6. **What does `ImagePullBackOff` mean?** The kubelet could not pull the image (`ErrImagePull`) and is waiting before trying again. The reason is in the events: wrong name/tag (`not found`), missing credentials (`unauthorized`), rate limit (`429`), wrong platform, or an unreachable registry.
7. **Why can a Pod remain `Pending`?** The scheduler cannot place it: requests larger than any node's free allocatable CPU/memory, a nodeSelector/affinity no node matches, taints without tolerations, or an unbound PVC. The `FailedScheduling` event says which.
8. **Why can a Service have no endpoints?** Its selector matches no Pods (typo or wrong labels), the matching Pods are not Ready (readiness probe failing, see Session 13), or they are in another namespace. With endpoints present but on the wrong `targetPort`, the Service still fails.
9. **What is the relationship between a Service selector and Pod labels?** The Service has no fixed list of Pods. The EndpointSlice controller continuously selects all Ready Pods in the namespace whose labels contain every key=value of the selector and puts their IPs in the EndpointSlices. Change either side and the endpoints change.
10. **What is Kubernetes DNS?** CoreDNS, running in `kube-system` behind the `kube-dns` Service (10.96.0.10). Every Pod's `/etc/resolv.conf` points to it. It answers `<service>.<namespace>.svc.cluster.local` with the Service's ClusterIP, and the search domains let Pods use just `<service>` inside the same namespace or `<service>.<namespace>` across namespaces.

## Cleanup

```bash
$ kubectl delete namespace s14-commands s14-triage s14-containercreating s14-service s14-netpol s14-config s14-mini
namespace "s14-commands" deleted
namespace "s14-triage" deleted
namespace "s14-containercreating" deleted
namespace "s14-service" deleted
namespace "s14-netpol" deleted
namespace "s14-config" deleted
namespace "s14-mini" deleted
```

The private kubeconfig copy used for the triage script was deleted too.

## What I learned

- Work from the outside in, in a fixed order: `get` -> `describe`/events -> `logs` (`--previous`) -> `exec` -> test the path (Pod IP, Service, DNS name) -> fix -> verify. Most of my root causes were visible in the first two steps.
- The status name already narrows things down. `Pending` is scheduling. `ContainerCreating` / `CreateContainerConfigError` mean volumes or config are missing before the container starts. `ErrImagePull` is the registry. `CrashLoopBackOff` / `OOMKilled` is the process itself.
- "Running" does not mean "working": the DNS scenario hid its error with `curl -s || true`, and a Service with a typo in its selector looks fine until you check its endpoints.
- `Connection refused` (no endpoints or wrong port) and `timed out` (dropped by a NetworkPolicy) point to different layers. I checked that kindnet on this cluster really enforces NetworkPolicy instead of assuming it.
- A Pod's default `restartPolicy: Always` turns even a successful exit into a restart loop. One-off work belongs in a Job.
- On a shared cluster, run scripts that use the default namespace with a private kubeconfig copy instead of changing the shared context.
