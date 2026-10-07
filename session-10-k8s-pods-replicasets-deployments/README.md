# Session 10: Kubernetes Pods, ReplicaSets & Deployments

**Name:** Vansh Srivastava
**Enrollment No.:** 24bcs10567
**Session:** 10

This session is about the workload objects. In Task 1 I implemented the four deployment strategies from the course folders (Rolling Update, Blue-Green, Canary, Recreate) and measured each one with a client Pod that kept sending requests while the change happened. In Task 2 I applied every Pod lifecycle example (12 YAML files) and recorded what Kubernetes did with each one. I also ran the basic Pod, ReplicaSet, Deployment, DaemonSet and StatefulSet examples and the two troubleshooting drills from the course folder.

## Folder structure

```text
session-10-k8s-pods-replicasets-deployments/
├── README.md
├── .gitignore
├── client/
│   └── curl-client.yaml          # s10-client namespace + curl Pod I used to send requests inside the cluster
├── 01-rolling-update/            # deployment-v1.yaml, deployment-v2.yaml, service.yaml
├── 02-blue-green/                # deployment-blue.yaml, deployment-green.yaml, service-blue.yaml, service-green.yaml
├── 03-canary/                    # deployment-stable.yaml (9 replicas), deployment-canary.yaml (1 replica), service.yaml
├── 04-recreate/                  # deployment-v1.yaml, deployment-v2.yaml, service.yaml
├── pod-lifecycle/                # 01-running.yaml ... 12-termination.yaml (one file per lifecycle situation)
├── core-objects/
│   ├── pod.yaml                  # single Pod with requests/limits
│   ├── replicaset.yaml           # bare ReplicaSet (3 Python HTTP servers)
│   ├── deployment-v1.yaml        # Deployment v1.0.0 (maxSurge 1, maxUnavailable 1)
│   ├── deployment-v2.yaml        # Deployment v2.0.0 (maxSurge 1, maxUnavailable 0)
│   ├── daemonset.yaml            # one logging-agent Pod per node
│   ├── statefulset.yaml          # my lightweight StatefulSet + headless Service + PVC per Pod
│   └── statefulset-mysql-course.yaml  # the course's MySQL StatefulSet, kept for reference (not run, see below)
└── troubleshooting/
    ├── broken-image.yaml         # rollout to a tag that does not exist
    └── selector-mismatch.yaml    # Deployment whose selector does not match its template labels
```

All YAML files except `client/curl-client.yaml` and `core-objects/statefulset.yaml` come from the course repository (Nency-Ravaliya/devops-heros, folder `session10-k8s-core-objects`). Each copied file starts with a two-line comment that names its source and any change I made.

## Environment

```text
macOS 26 on Apple Silicon (arm64), Docker from Colima
minikube v1.39.0 (docker driver, containerd 2.3.4), Kubernetes v1.37.0, kubectl v1.37.1
Shared single-node cluster; I only used namespaces starting with s10-
```

Three changes I had to make to the course files, and why:

1. **Image registry.** Docker Hub was answering anonymous pulls from this network with `429 Too Many Requests` (shown in Session 09). I changed `nginx:…`, `busybox:…` and `python:…` to `public.ecr.aws/docker/library/…`, which is AWS's mirror of the same Docker Hub official images. Tags are unchanged, and all of them have arm64 builds. The two intentionally broken images (`jakwehrgkaejw:kahsdfgkhj` and `yatri-backend:non-existent-tag-v999`) are untouched, so they fail for their own reason.
2. **NodePort numbers.** The course Services pin `nodePort: 30010/30020/30030/30040`. NodePorts are cluster-wide and this cluster is shared, so I removed those lines and let Kubernetes choose a free port. I tested every Service from a client Pod inside the cluster instead (the node IP is not reachable from macOS with the docker driver anyway).
3. **`02-pending.yaml`.** It asked for `cpu: 1, memory: 9Gi`. This node reports ~9.7 GiB allocatable and only ~0.5 GiB was requested, so that Pod would actually have been scheduled (and would have blocked everyone else's Pods). I raised it to `cpu: 32, memory: 64Gi` so it is impossible on any laptop.

The client Pod used for all traffic tests:

```bash
$ kubectl apply -f client/curl-client.yaml
namespace/s10-client created
pod/curl-client created
```

---

## Task 1: Deployment Strategies

### 01 Rolling Update

The Deployment runs 4 replicas of nginx 1.24 (v1) and is updated to nginx 1.25 (v2). The important part of [01-rolling-update/deployment-v2.yaml](01-rolling-update/deployment-v2.yaml):

```yaml
spec:
  replicas: 4
  strategy:
    type: RollingUpdate
    rollingUpdate:
      maxSurge: 1        # at most 4 + 1 = 5 Pods during the update
      maxUnavailable: 0  # never fewer than 4 ready Pods
  ...
          readinessProbe:      # a new Pod only counts as available after this passes
            httpGet: { path: /, port: 80 }
            initialDelaySeconds: 3
            periodSeconds: 5
```

A `postStart` hook writes a page containing `VERSION: v1` or `VERSION: v2`, so every response tells me which version served it.

**Create the Deployment (v1):**

```bash
$ kubectl create namespace s10-rolling
namespace/s10-rolling created
$ kubectl apply -n s10-rolling -f 01-rolling-update/deployment-v1.yaml -f 01-rolling-update/service.yaml
deployment.apps/app-rolling created
service/app-rolling-service created
$ kubectl rollout status deployment/app-rolling -n s10-rolling --timeout=180s
Waiting for deployment "app-rolling" rollout to finish: 0 of 4 updated replicas are available...
Waiting for deployment "app-rolling" rollout to finish: 1 of 4 updated replicas are available...
Waiting for deployment "app-rolling" rollout to finish: 2 of 4 updated replicas are available...
Waiting for deployment "app-rolling" rollout to finish: 3 of 4 updated replicas are available...
deployment "app-rolling" successfully rolled out
$ kubectl get deploy,rs,svc -n s10-rolling
NAME                          READY   UP-TO-DATE   AVAILABLE   AGE
deployment.apps/app-rolling   4/4     4            4           27s

NAME                                     DESIRED   CURRENT   READY   AGE
replicaset.apps/app-rolling-57f98bc9f6   4         4         4       27s

NAME                          TYPE       CLUSTER-IP      EXTERNAL-IP   PORT(S)        AGE
service/app-rolling-service   NodePort   10.103.241.46   <none>        80:32079/TCP   27s
$ kubectl get pods -n s10-rolling -l app=app-rolling --show-labels
NAME                           READY   STATUS    RESTARTS   AGE   LABELS
app-rolling-57f98bc9f6-2c6gf   1/1     Running   0          27s   app=app-rolling,pod-template-hash=57f98bc9f6,version=v1
app-rolling-57f98bc9f6-fb5kx   1/1     Running   0          27s   app=app-rolling,pod-template-hash=57f98bc9f6,version=v1
app-rolling-57f98bc9f6-hxdpp   1/1     Running   0          27s   app=app-rolling,pod-template-hash=57f98bc9f6,version=v1
app-rolling-57f98bc9f6-wllnr   1/1     Running   0          27s   app=app-rolling,pod-template-hash=57f98bc9f6,version=v1
$ kubectl exec -n s10-client curl-client -- curl -s http://app-rolling-service.s10-rolling
<html><body style="background:#1a1a2e;color:#e94560;font-family:monospace;font-size:3em;text-align:center;padding-top:20vh">
<p>VERSION: v1</p><p style="font-size:0.5em;color:#16213e">Rolling Update Demo</p></body></html>
```

**Perform the update.** Before applying v2 I started two background jobs: a Pod watch (each line prefixed with the time it arrived) and a loop in the client Pod that sends a request every 0.5 s and records the version or `FAILED`:

```bash
$ kubectl get pods -n s10-rolling -l app=app-rolling -L version -w | while read -r l; do echo "$(date +%H:%M:%S)  $l"; done > s10-ru-watch.txt &
$ kubectl exec -n s10-client curl-client -- sh -c 'for i in $(seq 1 90); do echo "$(date +%T) $(curl -s --max-time 2 http://app-rolling-service.s10-rolling | grep -o "VERSION: v[0-9]" || echo FAILED)"; sleep 0.5; done' > s10-ru-curl.txt &
```

```bash
$ kubectl apply -n s10-rolling -f 01-rolling-update/deployment-v2.yaml
deployment.apps/app-rolling configured
$ kubectl rollout status deployment/app-rolling -n s10-rolling --timeout=180s
Waiting for deployment "app-rolling" rollout to finish: 1 out of 4 new replicas have been updated...
Waiting for deployment "app-rolling" rollout to finish: 1 out of 4 new replicas have been updated...
Waiting for deployment "app-rolling" rollout to finish: 1 out of 4 new replicas have been updated...
Waiting for deployment "app-rolling" rollout to finish: 2 out of 4 new replicas have been updated...
Waiting for deployment "app-rolling" rollout to finish: 2 out of 4 new replicas have been updated...
Waiting for deployment "app-rolling" rollout to finish: 2 out of 4 new replicas have been updated...
Waiting for deployment "app-rolling" rollout to finish: 2 out of 4 new replicas have been updated...
Waiting for deployment "app-rolling" rollout to finish: 3 out of 4 new replicas have been updated...
Waiting for deployment "app-rolling" rollout to finish: 3 out of 4 new replicas have been updated...
Waiting for deployment "app-rolling" rollout to finish: 3 out of 4 new replicas have been updated...
Waiting for deployment "app-rolling" rollout to finish: 3 out of 4 new replicas have been updated...
Waiting for deployment "app-rolling" rollout to finish: 1 old replicas are pending termination...
Waiting for deployment "app-rolling" rollout to finish: 1 old replicas are pending termination...
Waiting for deployment "app-rolling" rollout to finish: 1 old replicas are pending termination...
deployment "app-rolling" successfully rolled out
```

**Old and new Pods side by side** (the watch output, local time; the update was applied at 23:25:54):

```text
23:25:51  NAME                           READY   STATUS    RESTARTS   AGE   VERSION
23:25:51  app-rolling-57f98bc9f6-2c6gf   1/1     Running   0          35s   v1
23:25:51  app-rolling-57f98bc9f6-fb5kx   1/1     Running   0          35s   v1
23:25:51  app-rolling-57f98bc9f6-hxdpp   1/1     Running   0          35s   v1
23:25:51  app-rolling-57f98bc9f6-wllnr   1/1     Running   0          35s   v1
23:25:55  app-rolling-5c98f4676c-zvrc9   0/1     Pending   0          0s    v2
23:25:55  app-rolling-5c98f4676c-zvrc9   0/1     Pending   0          0s    v2
23:25:55  app-rolling-5c98f4676c-zvrc9   0/1     ContainerCreating   0          0s    v2
23:25:55  app-rolling-5c98f4676c-zvrc9   0/1     ContainerCreating   0          0s    v2
23:25:58  app-rolling-5c98f4676c-zvrc9   0/1     Running             0          4s    v2
23:26:05  app-rolling-5c98f4676c-zvrc9   1/1     Running             0          10s   v2
23:26:05  app-rolling-5c98f4676c-zvrc9   1/1     Running             0          10s   v2
23:26:05  app-rolling-57f98bc9f6-fb5kx   1/1     Terminating         0          49s   v1
23:26:05  app-rolling-5c98f4676c-44l6s   0/1     Pending             0          0s    v2
23:26:05  app-rolling-57f98bc9f6-fb5kx   1/1     Terminating         0          49s   v1
23:26:05  app-rolling-5c98f4676c-44l6s   0/1     Pending             0          0s    v2
23:26:05  app-rolling-5c98f4676c-44l6s   0/1     ContainerCreating   0          0s    v2
23:26:05  app-rolling-57f98bc9f6-fb5kx   0/1     Completed           0          50s   v1
23:26:06  app-rolling-5c98f4676c-44l6s   0/1     ContainerCreating   0          1s    v2
23:26:06  app-rolling-57f98bc9f6-fb5kx   0/1     Completed           0          50s   v1
23:26:06  app-rolling-57f98bc9f6-fb5kx   0/1     Completed           0          50s   v1
23:26:06  app-rolling-5c98f4676c-44l6s   0/1     Running             0          1s    v2
23:26:12  app-rolling-5c98f4676c-44l6s   1/1     Running             0          7s    v2
23:26:12  app-rolling-5c98f4676c-44l6s   1/1     Running             0          7s    v2
23:26:12  app-rolling-57f98bc9f6-hxdpp   1/1     Terminating         0          56s   v1
23:26:12  app-rolling-5c98f4676c-gg5v7   0/1     Pending             0          0s    v2
23:26:12  app-rolling-57f98bc9f6-hxdpp   1/1     Terminating         0          56s   v1
23:26:12  app-rolling-5c98f4676c-gg5v7   0/1     Pending             0          0s    v2
23:26:12  app-rolling-5c98f4676c-gg5v7   0/1     ContainerCreating   0          0s    v2
23:26:12  app-rolling-57f98bc9f6-hxdpp   0/1     Completed           0          56s   v1
23:26:12  app-rolling-5c98f4676c-gg5v7   0/1     ContainerCreating   0          0s    v2
23:26:13  app-rolling-5c98f4676c-gg5v7   0/1     Running             0          1s    v2
23:26:13  app-rolling-57f98bc9f6-hxdpp   0/1     Completed           0          57s   v1
23:26:13  app-rolling-57f98bc9f6-hxdpp   0/1     Completed           0          57s   v1
23:26:18  app-rolling-5c98f4676c-gg5v7   1/1     Running             0          6s    v2
23:26:18  app-rolling-57f98bc9f6-2c6gf   1/1     Terminating         0          62s   v1
23:26:18  app-rolling-57f98bc9f6-2c6gf   1/1     Terminating         0          62s   v1
23:26:18  app-rolling-5c98f4676c-dnd6c   0/1     Pending             0          0s    v2
23:26:18  app-rolling-5c98f4676c-dnd6c   0/1     Pending             0          0s    v2
23:26:18  app-rolling-5c98f4676c-dnd6c   0/1     ContainerCreating   0          0s    v2
23:26:18  app-rolling-57f98bc9f6-2c6gf   0/1     Completed           0          62s   v1
23:26:18  app-rolling-5c98f4676c-dnd6c   0/1     ContainerCreating   0          0s    v2
23:26:19  app-rolling-5c98f4676c-dnd6c   0/1     Running             0          1s    v2
23:26:19  app-rolling-57f98bc9f6-2c6gf   0/1     Completed           0          63s   v1
23:26:19  app-rolling-57f98bc9f6-2c6gf   0/1     Completed           0          63s   v1
23:26:24  app-rolling-5c98f4676c-dnd6c   1/1     Running             0          6s    v2
23:26:24  app-rolling-57f98bc9f6-wllnr   1/1     Terminating         0          68s   v1
23:26:24  app-rolling-57f98bc9f6-wllnr   1/1     Terminating         0          68s   v1
23:26:24  app-rolling-57f98bc9f6-wllnr   0/1     Completed           0          68s   v1
23:26:25  app-rolling-57f98bc9f6-wllnr   0/1     Completed           0          69s   v1
23:26:25  app-rolling-57f98bc9f6-wllnr   0/1     Completed           0          69s   v1
```

Reading the timestamps, the pattern repeats four times: one new v2 Pod is created (surge to 5), it is `Running` but `0/1` until its readiness probe passes 6-10 s later, and only then is one v1 Pod terminated. At no point were fewer than 4 Pods ready, which is exactly `maxUnavailable: 0`.

**Traffic during the rollout.** Excerpt of the request loop (the client Pod's clock is UTC, so 17:56 here is 23:26 local). Around the middle of the rollout both versions answered at the same time:

```text
17:56:04 VERSION: v1
17:56:05 VERSION: v1
17:56:05 VERSION: v1
17:56:06 VERSION: v1
17:56:06 VERSION: v2
17:56:07 VERSION: v1
17:56:07 VERSION: v1
17:56:08 VERSION: v1
17:56:08 VERSION: v1
17:56:09 VERSION: v1
17:56:09 VERSION: v1
17:56:10 VERSION: v1
17:56:10 VERSION: v2
17:56:11 VERSION: v1
17:56:11 VERSION: v2
17:56:12 VERSION: v2
17:56:12 VERSION: v1
17:56:13 VERSION: v2
17:56:13 VERSION: v2
17:56:14 VERSION: v1
17:56:14 VERSION: v1
17:56:15 VERSION: v2
17:56:15 VERSION: v1
17:56:16 VERSION: v2
17:56:16 VERSION: v1
17:56:17 VERSION: v1
17:56:17 VERSION: v2
17:56:18 VERSION: v1
17:56:19 VERSION: v2
17:56:19 VERSION: v2
17:56:20 VERSION: v2
17:56:20 VERSION: v2
17:56:21 VERSION: v2
17:56:21 VERSION: v2
17:56:21 VERSION: v1
```

```bash
$ awk '{print $2, $3}' s10-ru-curl.txt | sort | uniq -c
  48 VERSION: v1
  42 VERSION: v2
$ grep -c FAILED s10-ru-curl.txt
0
```

90 requests, 48 answered by v1 and 42 by v2, **0 failed**: a zero-downtime update.

**ReplicaSets after the update:**

```bash
$ kubectl get rs -n s10-rolling -L version
NAME                     DESIRED   CURRENT   READY   AGE   VERSION
app-rolling-57f98bc9f6   0         0         0       97s   v1
app-rolling-5c98f4676c   4         4         4       58s   v2
$ kubectl get pods -n s10-rolling -l app=app-rolling --show-labels
NAME                           READY   STATUS    RESTARTS   AGE   LABELS
app-rolling-5c98f4676c-44l6s   1/1     Running   0          49s   app=app-rolling,pod-template-hash=5c98f4676c,version=v2
app-rolling-5c98f4676c-dnd6c   1/1     Running   0          36s   app=app-rolling,pod-template-hash=5c98f4676c,version=v2
app-rolling-5c98f4676c-gg5v7   1/1     Running   0          42s   app=app-rolling,pod-template-hash=5c98f4676c,version=v2
app-rolling-5c98f4676c-zvrc9   1/1     Running   0          59s   app=app-rolling,pod-template-hash=5c98f4676c,version=v2
$ kubectl describe deployment app-rolling -n s10-rolling | grep -E '^(StrategyType|RollingUpdateStrategy|OldReplicaSets|NewReplicaSet)'
StrategyType:           RollingUpdate
RollingUpdateStrategy:  0 max unavailable, 1 max surge
OldReplicaSets:  app-rolling-57f98bc9f6 (0/0 replicas created)
NewReplicaSet:   app-rolling-5c98f4676c (4/4 replicas created)
$ kubectl describe deployment app-rolling -n s10-rolling | sed -n '/^Events:/,$p'
Events:
  Type    Reason             Age   From                   Message
  ----    ------             ----  ----                   -------
  Normal  ScalingReplicaSet  98s   deployment-controller  Scaled up replica set app-rolling-57f98bc9f6 from 0 to 4
  Normal  ScalingReplicaSet  59s   deployment-controller  Scaled up replica set app-rolling-5c98f4676c from 0 to 1
  Normal  ScalingReplicaSet  49s   deployment-controller  Scaled down replica set app-rolling-57f98bc9f6 from 4 to 3
  Normal  ScalingReplicaSet  49s   deployment-controller  Scaled up replica set app-rolling-5c98f4676c from 1 to 2
  Normal  ScalingReplicaSet  42s   deployment-controller  Scaled down replica set app-rolling-57f98bc9f6 from 3 to 2
  Normal  ScalingReplicaSet  42s   deployment-controller  Scaled up replica set app-rolling-5c98f4676c from 2 to 3
  Normal  ScalingReplicaSet  36s   deployment-controller  Scaled down replica set app-rolling-57f98bc9f6 from 2 to 1
  Normal  ScalingReplicaSet  36s   deployment-controller  Scaled up replica set app-rolling-5c98f4676c from 3 to 4
  Normal  ScalingReplicaSet  30s   deployment-controller  Scaled down replica set app-rolling-57f98bc9f6 from 1 to 0
$ kubectl exec -n s10-client curl-client -- curl -s http://app-rolling-service.s10-rolling | grep -o 'VERSION: v[0-9]'
VERSION: v2
$ kubectl rollout history deployment/app-rolling -n s10-rolling
deployment.apps/app-rolling 
REVISION  CHANGE-CAUSE
1         <none>
2         <none>
```

The Deployment created a second ReplicaSet (`5c98f4676c`, v2) and moved the replicas over one by one (the events read 0→1 up, 4→3 down, 1→2 up, ...). The old ReplicaSet is kept at 0 replicas so a rollback is possible:

```bash
$ kubectl rollout undo deployment/app-rolling -n s10-rolling
Warning: resource deployments/app-rolling was previously managed with 'kubectl apply'. Rolling back will not update the kubectl.kubernetes.io/last-applied-configuration annotation, which may cause unexpected behavior on future 'kubectl apply' operations. Consider using 'kubectl apply' with your previous configuration file instead.
deployment.apps/app-rolling rolled back
$ kubectl rollout status deployment/app-rolling -n s10-rolling --timeout=180s
Waiting for deployment "app-rolling" rollout to finish: 1 out of 4 new replicas have been updated...
Waiting for deployment "app-rolling" rollout to finish: 1 out of 4 new replicas have been updated...
Waiting for deployment "app-rolling" rollout to finish: 1 out of 4 new replicas have been updated...
Waiting for deployment "app-rolling" rollout to finish: 2 out of 4 new replicas have been updated...
Waiting for deployment "app-rolling" rollout to finish: 2 out of 4 new replicas have been updated...
Waiting for deployment "app-rolling" rollout to finish: 2 out of 4 new replicas have been updated...
Waiting for deployment "app-rolling" rollout to finish: 2 out of 4 new replicas have been updated...
Waiting for deployment "app-rolling" rollout to finish: 3 out of 4 new replicas have been updated...
Waiting for deployment "app-rolling" rollout to finish: 3 out of 4 new replicas have been updated...
Waiting for deployment "app-rolling" rollout to finish: 3 out of 4 new replicas have been updated...
Waiting for deployment "app-rolling" rollout to finish: 3 out of 4 new replicas have been updated...
Waiting for deployment "app-rolling" rollout to finish: 1 old replicas are pending termination...
Waiting for deployment "app-rolling" rollout to finish: 1 old replicas are pending termination...
Waiting for deployment "app-rolling" rollout to finish: 1 old replicas are pending termination...
deployment "app-rolling" successfully rolled out
$ kubectl get rs -n s10-rolling -L version
NAME                     DESIRED   CURRENT   READY   AGE    VERSION
app-rolling-57f98bc9f6   4         4         4       2m4s   v1
app-rolling-5c98f4676c   0         0         0       85s    v2
$ kubectl rollout history deployment/app-rolling -n s10-rolling
deployment.apps/app-rolling 
REVISION  CHANGE-CAUSE
2         <none>
3         <none>
$ sleep 3; kubectl get pods -n s10-rolling -l app=app-rolling -L version
NAME                           READY   STATUS    RESTARTS   AGE   VERSION
app-rolling-57f98bc9f6-6d8kf   1/1     Running   0          23s   v1
app-rolling-57f98bc9f6-878rd   1/1     Running   0          11s   v1
app-rolling-57f98bc9f6-hw4kv   1/1     Running   0          17s   v1
app-rolling-57f98bc9f6-qrkj7   1/1     Running   0          29s   v1
$ kubectl exec -n s10-client curl-client -- curl -s http://app-rolling-service.s10-rolling | grep -o 'VERSION: v[0-9]'
VERSION: v1
```

The rollback is just another rolling update in the opposite direction: the old ReplicaSet `57f98bc9f6` was scaled back up to 4 and revision 1 became revision 3. (The warning is kubectl reminding me that the YAML file on disk still says v2.)

### 02 Blue-Green

Two complete Deployments run side by side: `app-blue` (v1, label `slot: blue`) and `app-green` (v2, label `slot: green`). One Service, `myapp-service`, decides which one is live through its selector. The only difference between [service-blue.yaml](02-blue-green/service-blue.yaml) and [service-green.yaml](02-blue-green/service-green.yaml) is:

```yaml
  selector:
    app: myapp
    slot: blue     # service-green.yaml has: slot: green
```

**Create Blue (live) and the Service:**

```bash
$ kubectl create namespace s10-bluegreen
namespace/s10-bluegreen created
$ kubectl apply -n s10-bluegreen -f 02-blue-green/deployment-blue.yaml -f 02-blue-green/service-blue.yaml
deployment.apps/app-blue created
service/myapp-service created
$ kubectl rollout status deployment/app-blue -n s10-bluegreen --timeout=180s
Waiting for deployment "app-blue" rollout to finish: 0 of 3 updated replicas are available...
Waiting for deployment "app-blue" rollout to finish: 1 of 3 updated replicas are available...
Waiting for deployment "app-blue" rollout to finish: 2 of 3 updated replicas are available...
deployment "app-blue" successfully rolled out
$ for i in 1 2 3; do kubectl exec -n s10-client curl-client -- curl -s http://myapp-service.s10-bluegreen | grep -oE '(BLUE|GREEN) ENVIRONMENT'; done
command terminated with exit code 7
command terminated with exit code 7
command terminated with exit code 7
```

The first three requests, sent the moment the rollout finished, failed with curl exit code 7 (connection refused). The Service and its endpoints existed, but kube-proxy had not yet written the iptables rules for the brand-new Service (it applies changes in batches, typically within a second or two). A few seconds later every request reached Blue:

```bash
$ for i in 1 2 3 4 5; do kubectl exec -n s10-client curl-client -- curl -s http://myapp-service.s10-bluegreen | grep -oE '(BLUE|GREEN) ENVIRONMENT'; done
BLUE ENVIRONMENT
BLUE ENVIRONMENT
BLUE ENVIRONMENT
BLUE ENVIRONMENT
BLUE ENVIRONMENT
```

**Create Green (standby).** Green gets no traffic yet, because the Service selector still says `slot: blue`. The EndpointSlice holds only the three Blue Pod IPs:

```bash
$ kubectl apply -n s10-bluegreen -f 02-blue-green/deployment-green.yaml
deployment.apps/app-green created
$ kubectl rollout status deployment/app-green -n s10-bluegreen --timeout=180s
Waiting for deployment "app-green" rollout to finish: 0 of 3 updated replicas are available...
Waiting for deployment "app-green" rollout to finish: 1 of 3 updated replicas are available...
Waiting for deployment "app-green" rollout to finish: 2 of 3 updated replicas are available...
deployment "app-green" successfully rolled out
$ kubectl get deploy,pods -n s10-bluegreen -L slot,version
NAME                        READY   UP-TO-DATE   AVAILABLE   AGE   SLOT    VERSION
deployment.apps/app-blue    3/3     3            3           13s   blue    v1
deployment.apps/app-green   3/3     3            3           6s    green   v2

NAME                             READY   STATUS    RESTARTS   AGE   SLOT    VERSION
pod/app-blue-ddd4dfc-lkq5w       1/1     Running   0          13s   blue    v1
pod/app-blue-ddd4dfc-n7ndd       1/1     Running   0          13s   blue    v1
pod/app-blue-ddd4dfc-t2z5p       1/1     Running   0          13s   blue    v1
pod/app-green-7bc6f86c6b-46mt6   1/1     Running   0          6s    green   v2
pod/app-green-7bc6f86c6b-4dmdb   1/1     Running   0          6s    green   v2
pod/app-green-7bc6f86c6b-jgkxn   1/1     Running   0          6s    green   v2
$ kubectl get svc myapp-service -n s10-bluegreen -o wide
NAME            TYPE       CLUSTER-IP    EXTERNAL-IP   PORT(S)        AGE   SELECTOR
myapp-service   NodePort   10.104.3.25   <none>        80:31418/TCP   13s   app=myapp,slot=blue
$ kubectl get endpointslices -n s10-bluegreen -l kubernetes.io/service-name=myapp-service
NAME                  ADDRESSTYPE   PORTS   ENDPOINTS                             AGE
myapp-service-rqz46   IPv4          80      10.244.0.75,10.244.0.76,10.244.0.77   13s
$ kubectl get pods -n s10-bluegreen -l slot=blue -o custom-columns=NAME:.metadata.name,IP:.status.podIP
NAME                     IP
app-blue-ddd4dfc-lkq5w   10.244.0.77
app-blue-ddd4dfc-n7ndd   10.244.0.76
app-blue-ddd4dfc-t2z5p   10.244.0.75
$ kubectl get pods -n s10-bluegreen -l slot=green -o custom-columns=NAME:.metadata.name,IP:.status.podIP
NAME                         IP
app-green-7bc6f86c6b-46mt6   10.244.0.78
app-green-7bc6f86c6b-4dmdb   10.244.0.79
app-green-7bc6f86c6b-jgkxn   10.244.0.80
```

**Switch traffic by changing the Service selector.** I kept a request loop running in the client Pod (one request every 0.5 s) and applied `service-green.yaml` at 17:58:11 UTC:

```bash
$ kubectl apply -n s10-bluegreen -f 02-blue-green/service-green.yaml
service/myapp-service configured
```

```text
17:58:09 BLUE ENVIRONMENT
17:58:09 BLUE ENVIRONMENT
17:58:10 BLUE ENVIRONMENT
17:58:10 BLUE ENVIRONMENT
17:58:11 BLUE ENVIRONMENT
17:58:11 BLUE ENVIRONMENT
17:58:12 GREEN ENVIRONMENT
17:58:12 GREEN ENVIRONMENT
17:58:13 GREEN ENVIRONMENT
17:58:13 GREEN ENVIRONMENT
17:58:14 GREEN ENVIRONMENT
17:58:14 GREEN ENVIRONMENT
```

```bash
$ awk '{print $2, $3}' s10-bg-loop.txt | sort | uniq -c
  12 BLUE ENVIRONMENT
  18 GREEN ENVIRONMENT
$ grep -c FAILED s10-bg-loop.txt
0
```

The switch is instant and all-or-nothing: every request before 17:58:12 got Blue, every request after got Green, and none failed. The Service now points at the Green Pod IPs:

```bash
$ kubectl get svc myapp-service -n s10-bluegreen -o wide
NAME            TYPE       CLUSTER-IP    EXTERNAL-IP   PORT(S)        AGE   SELECTOR
myapp-service   NodePort   10.104.3.25   <none>        80:31418/TCP   49s   app=myapp,slot=green
$ kubectl get endpointslices -n s10-bluegreen -l kubernetes.io/service-name=myapp-service
NAME                  ADDRESSTYPE   PORTS   ENDPOINTS                             AGE
myapp-service-rqz46   IPv4          80      10.244.0.78,10.244.0.80,10.244.0.79   49s
$ for i in 1 2 3 4 5; do kubectl exec -n s10-client curl-client -- curl -s http://myapp-service.s10-bluegreen | grep -oE '(BLUE|GREEN) ENVIRONMENT|Version: v[0-9]'; done
GREEN ENVIRONMENT
Version: v2
GREEN ENVIRONMENT
Version: v2
GREEN ENVIRONMENT
Version: v2
GREEN ENVIRONMENT
Version: v2
GREEN ENVIRONMENT
Version: v2
```

**Rollback is the same operation in reverse.** Blue is still running, so going back takes one patch:

```bash
$ kubectl patch svc myapp-service -n s10-bluegreen -p '{"spec":{"selector":{"app":"myapp","slot":"blue"}}}'
service/myapp-service patched
$ kubectl get svc myapp-service -n s10-bluegreen -o jsonpath='{.spec.selector}{"\n"}'
{"app":"myapp","slot":"blue"}
$ for i in 1 2 3; do kubectl exec -n s10-client curl-client -- curl -s http://myapp-service.s10-bluegreen | grep -oE '(BLUE|GREEN) ENVIRONMENT'; done
BLUE ENVIRONMENT
BLUE ENVIRONMENT
BLUE ENVIRONMENT
```

**Final promotion.** I switched to Green again and scaled Blue to 0 to free its resources:

```bash
$ kubectl apply -n s10-bluegreen -f 02-blue-green/service-green.yaml
service/myapp-service configured
$ kubectl scale deployment app-blue -n s10-bluegreen --replicas=0
deployment.apps/app-blue scaled
$ kubectl get deploy -n s10-bluegreen
NAME        READY   UP-TO-DATE   AVAILABLE   AGE
app-blue    3/0     3            3           50s
app-green   3/3     3            3           43s
$ kubectl exec -n s10-client curl-client -- curl -s http://myapp-service.s10-bluegreen | grep -oE '(BLUE|GREEN) ENVIRONMENT'
command terminated with exit code 7
```

The single request I sent immediately after these changes failed with exit code 7, the same short kube-proxy sync gap seen at the start. Re-checking a few seconds later, Green answered every time and Blue had finished scaling down:

```bash
$ for i in 1 2 3; do kubectl exec -n s10-client curl-client -- curl -s http://myapp-service.s10-bluegreen | grep -oE '(BLUE|GREEN) ENVIRONMENT'; done
GREEN ENVIRONMENT
GREEN ENVIRONMENT
GREEN ENVIRONMENT
$ kubectl get deploy -n s10-bluegreen
NAME        READY   UP-TO-DATE   AVAILABLE   AGE
app-blue    0/0     0            0           66s
app-green   3/3     3            3           59s
```

Lesson: a selector switch is fast, but not literally atomic for a client that connects in the same second. In production I would add client retries or do the switch at a load balancer / Ingress.

### 03 Canary

Stable (v1) runs 9 replicas and the canary (v2) runs 1. Both have the label `app: myapp-canary`, and the single Service selects only that label, so it load-balances over all 10 Pods. The expected split is therefore 9:1, i.e. about 10% canary traffic.

```yaml
# 03-canary/service.yaml
  selector:
    app: myapp-canary        # common label: matches stable AND canary Pods
# deployment-stable.yaml: replicas: 9, labels track: stable, version: v1
# deployment-canary.yaml: replicas: 1, labels track: canary, version: v2
```

```bash
$ kubectl create namespace s10-canary
namespace/s10-canary created
$ kubectl apply -n s10-canary -f 03-canary/deployment-stable.yaml -f 03-canary/service.yaml
deployment.apps/app-stable created
service/myapp-canary-service created
$ kubectl rollout status deployment/app-stable -n s10-canary --timeout=180s
Waiting for deployment "app-stable" rollout to finish: 0 of 9 updated replicas are available...
Waiting for deployment "app-stable" rollout to finish: 1 of 9 updated replicas are available...
Waiting for deployment "app-stable" rollout to finish: 2 of 9 updated replicas are available...
Waiting for deployment "app-stable" rollout to finish: 3 of 9 updated replicas are available...
Waiting for deployment "app-stable" rollout to finish: 4 of 9 updated replicas are available...
Waiting for deployment "app-stable" rollout to finish: 5 of 9 updated replicas are available...
Waiting for deployment "app-stable" rollout to finish: 6 of 9 updated replicas are available...
Waiting for deployment "app-stable" rollout to finish: 7 of 9 updated replicas are available...
Waiting for deployment "app-stable" rollout to finish: 8 of 9 updated replicas are available...
deployment "app-stable" successfully rolled out
$ kubectl apply -n s10-canary -f 03-canary/deployment-canary.yaml
deployment.apps/app-canary created
$ kubectl rollout status deployment/app-canary -n s10-canary --timeout=180s
Waiting for deployment "app-canary" rollout to finish: 0 of 1 updated replicas are available...
deployment "app-canary" successfully rolled out
$ kubectl get deploy -n s10-canary -L track,version
NAME         READY   UP-TO-DATE   AVAILABLE   AGE   TRACK    VERSION
app-canary   1/1     1            1           6s    canary   v2
app-stable   9/9     9            9           14s   stable   v1
$ kubectl get pods -n s10-canary -L track,version
NAME                         READY   STATUS    RESTARTS   AGE   TRACK    VERSION
app-canary-f96bb5df-chv94    1/1     Running   0          6s    canary   v2
app-stable-794946f46-2c77f   1/1     Running   0          14s   stable   v1
app-stable-794946f46-dlbfc   1/1     Running   0          14s   stable   v1
app-stable-794946f46-jvg62   1/1     Running   0          14s   stable   v1
app-stable-794946f46-mts4j   1/1     Running   0          14s   stable   v1
app-stable-794946f46-p85rf   1/1     Running   0          14s   stable   v1
app-stable-794946f46-p9zfw   1/1     Running   0          14s   stable   v1
app-stable-794946f46-pxpng   1/1     Running   0          14s   stable   v1
app-stable-794946f46-rq5fg   1/1     Running   0          14s   stable   v1
app-stable-794946f46-zwfcb   1/1     Running   0          14s   stable   v1
$ kubectl get svc myapp-canary-service -n s10-canary -o wide
NAME                   TYPE       CLUSTER-IP       EXTERNAL-IP   PORT(S)        AGE   SELECTOR
myapp-canary-service   NodePort   10.111.158.214   <none>        80:31676/TCP   14s   app=myapp-canary
$ kubectl get endpointslices -n s10-canary -o custom-columns=NAME:.metadata.name,ENDPOINTS:.endpoints[*].addresses[0]
NAME                         ENDPOINTS
myapp-canary-service-5dp5v   10.244.0.89,10.244.0.81,10.244.0.86,10.244.0.87,10.244.0.84,10.244.0.85,10.244.0.83,10.244.0.82,10.244.0.88,10.244.0.90
```

**Verify both versions with a loop of 20 requests and count the responses:**

```bash
$ kubectl exec -n s10-client curl-client -- sh -c 'for i in $(seq 1 20); do curl -s http://myapp-canary-service.s10-canary | grep -oE "(STABLE|CANARY) v[0-9]"; done' | sort | uniq -c
   2 CANARY v2
  18 STABLE v1
```

2 out of 20 requests (10%) reached the canary. Because kube-proxy picks a backend at random for each new connection, a 20-request sample is noisy, so I also sent 200:

```bash
$ kubectl exec -n s10-client curl-client -- sh -c 'for i in $(seq 1 200); do curl -s http://myapp-canary-service.s10-canary | grep -oE "(STABLE|CANARY) v[0-9]"; done' | sort | uniq -c
  24 CANARY v2
 176 STABLE v1
```

24/200 = 12% canary, close to the expected 10%.

**Promoting the canary step by step** means changing the replica ratio. I went to 5 stable + 5 canary (a 50/50 split):

```bash
$ kubectl scale deployment app-stable -n s10-canary --replicas=5 && kubectl scale deployment app-canary -n s10-canary --replicas=5
deployment.apps/app-stable scaled
deployment.apps/app-canary scaled
$ kubectl rollout status deployment/app-canary -n s10-canary --timeout=120s
Waiting for deployment "app-canary" rollout to finish: 1 out of 5 new replicas have been updated...
Waiting for deployment "app-canary" rollout to finish: 1 of 5 updated replicas are available...
Waiting for deployment "app-canary" rollout to finish: 2 of 5 updated replicas are available...
Waiting for deployment "app-canary" rollout to finish: 3 of 5 updated replicas are available...
Waiting for deployment "app-canary" rollout to finish: 4 of 5 updated replicas are available...
deployment "app-canary" successfully rolled out
$ sleep 5; kubectl get deploy -n s10-canary -L track,version
NAME         READY   UP-TO-DATE   AVAILABLE   AGE   TRACK    VERSION
app-canary   5/5     5            5           38s   canary   v2
app-stable   5/5     5            5           46s   stable   v1
$ kubectl exec -n s10-client curl-client -- sh -c 'for i in $(seq 1 200); do curl -s http://myapp-canary-service.s10-canary | grep -oE "(STABLE|CANARY) v[0-9]"; done' | sort | uniq -c
  85 CANARY v2
 115 STABLE v1
```

85/200 = 42.5% canary, roughly half. The limitation of this method is visible here: the traffic split can only be as fine as the Pod ratio (10% needs 10 Pods, 1% would need 100), and it is random per connection. Tools such as Istio, Argo Rollouts or ingress-nginx canary annotations split by exact percentage.

### 04 Recreate

`strategy: type: Recreate` tells the Deployment to delete **all** old Pods before it creates any new one. There is no readiness probe in these files, so a Pod is ready as soon as nginx starts.

```bash
$ kubectl create namespace s10-recreate
namespace/s10-recreate created
$ kubectl apply -n s10-recreate -f 04-recreate/deployment-v1.yaml -f 04-recreate/service.yaml
deployment.apps/app-recreate created
service/app-recreate-service created
$ kubectl rollout status deployment/app-recreate -n s10-recreate --timeout=180s
Waiting for deployment "app-recreate" rollout to finish: 0 of 3 updated replicas are available...
Waiting for deployment "app-recreate" rollout to finish: 1 of 3 updated replicas are available...
Waiting for deployment "app-recreate" rollout to finish: 2 of 3 updated replicas are available...
deployment "app-recreate" successfully rolled out
$ kubectl get pods -n s10-recreate -L version
NAME                           READY   STATUS    RESTARTS   AGE   VERSION
app-recreate-c5fdd5594-9pc22   1/1     Running   0          1s    v1
app-recreate-c5fdd5594-9rrm6   1/1     Running   0          1s    v1
app-recreate-c5fdd5594-b2sbg   1/1     Running   0          1s    v1
$ kubectl describe deployment app-recreate -n s10-recreate | grep -E '^StrategyType'
StrategyType:       Recreate
```

**Update with a Pod watch and a request loop running** (the update was applied at 23:30:04):

```bash
$ kubectl apply -n s10-recreate -f 04-recreate/deployment-v2.yaml
deployment.apps/app-recreate configured
$ kubectl rollout status deployment/app-recreate -n s10-recreate --timeout=180s
Waiting for deployment "app-recreate" rollout to finish: 0 out of 3 new replicas have been updated...
Waiting for deployment "app-recreate" rollout to finish: 0 out of 3 new replicas have been updated...
Waiting for deployment "app-recreate" rollout to finish: 0 out of 3 new replicas have been updated...
Waiting for deployment "app-recreate" rollout to finish: 0 out of 3 new replicas have been updated...
Waiting for deployment "app-recreate" rollout to finish: 0 out of 3 new replicas have been updated...
Waiting for deployment "app-recreate" rollout to finish: 0 of 3 updated replicas are available...
Waiting for deployment "app-recreate" rollout to finish: 1 of 3 updated replicas are available...
Waiting for deployment "app-recreate" rollout to finish: 2 of 3 updated replicas are available...
deployment "app-recreate" successfully rolled out
```

```text
23:30:00  NAME                           READY   STATUS    RESTARTS   AGE   VERSION
23:30:00  app-recreate-c5fdd5594-9pc22   1/1     Running   0          14s   v1
23:30:00  app-recreate-c5fdd5594-9rrm6   1/1     Running   0          14s   v1
23:30:00  app-recreate-c5fdd5594-b2sbg   1/1     Running   0          14s   v1
23:30:04  app-recreate-c5fdd5594-9rrm6   1/1     Terminating   0          18s   v1
23:30:04  app-recreate-c5fdd5594-9pc22   1/1     Terminating   0          18s   v1
23:30:04  app-recreate-c5fdd5594-b2sbg   1/1     Terminating   0          18s   v1
23:30:04  app-recreate-c5fdd5594-9rrm6   1/1     Terminating   0          18s   v1
23:30:04  app-recreate-c5fdd5594-b2sbg   1/1     Terminating   0          18s   v1
23:30:04  app-recreate-c5fdd5594-9pc22   1/1     Terminating   0          18s   v1
23:30:04  app-recreate-c5fdd5594-9rrm6   0/1     Completed     0          19s   v1
23:30:04  app-recreate-c5fdd5594-9pc22   0/1     Completed     0          19s   v1
23:30:05  app-recreate-c5fdd5594-b2sbg   0/1     Completed     0          19s   v1
23:30:05  app-recreate-77c5dc4778-rl649   0/1     Pending       0          0s    v2
23:30:05  app-recreate-77c5dc4778-2l49x   0/1     Pending       0          0s    v2
23:30:05  app-recreate-77c5dc4778-rl649   0/1     Pending       0          0s    v2
23:30:05  app-recreate-77c5dc4778-p4vwn   0/1     Pending       0          0s    v2
23:30:05  app-recreate-77c5dc4778-2l49x   0/1     Pending       0          0s    v2
23:30:05  app-recreate-77c5dc4778-p4vwn   0/1     Pending       0          0s    v2
23:30:05  app-recreate-77c5dc4778-rl649   0/1     ContainerCreating   0          0s    v2
23:30:05  app-recreate-77c5dc4778-p4vwn   0/1     ContainerCreating   0          0s    v2
23:30:05  app-recreate-77c5dc4778-2l49x   0/1     ContainerCreating   0          0s    v2
23:30:05  app-recreate-c5fdd5594-9pc22    0/1     Completed           0          19s   v1
23:30:05  app-recreate-c5fdd5594-9pc22    0/1     Completed           0          19s   v1
23:30:05  app-recreate-c5fdd5594-9rrm6    0/1     Completed           0          19s   v1
23:30:05  app-recreate-c5fdd5594-9rrm6    0/1     Completed           0          19s   v1
23:30:05  app-recreate-c5fdd5594-b2sbg    0/1     Completed           0          19s   v1
23:30:05  app-recreate-c5fdd5594-b2sbg    0/1     Completed           0          19s   v1
23:30:05  app-recreate-77c5dc4778-rl649   0/1     ContainerCreating   0          0s    v2
23:30:05  app-recreate-77c5dc4778-p4vwn   0/1     ContainerCreating   0          0s    v2
23:30:05  app-recreate-77c5dc4778-2l49x   0/1     ContainerCreating   0          0s    v2
23:30:05  app-recreate-77c5dc4778-rl649   1/1     Running             0          0s    v2
23:30:05  app-recreate-77c5dc4778-p4vwn   1/1     Running             0          0s    v2
23:30:05  app-recreate-77c5dc4778-2l49x   1/1     Running             0          0s    v2
```

All three v1 Pods went to `Terminating` at 23:30:04, and the v2 Pods (`77c5dc4778-*`) were only created at 23:30:05, after the old ones had `Completed`. During that gap nothing was serving. The request loop caught it:

```text
18:00:02 VERSION: v1
18:00:03 VERSION: v1
18:00:03 VERSION: v1
18:00:04 VERSION: v1
18:00:04 FAILED
18:00:05 FAILED
18:00:05 FAILED
18:00:06 VERSION: v2
18:00:06 VERSION: v2
18:00:07 VERSION: v2
18:00:07 VERSION: v2
18:00:08 VERSION: v2
```

```bash
$ awk '{print $2, $3}' s10-rec-loop.txt | sort | uniq -c
   3 FAILED 
   8 VERSION: v1
  39 VERSION: v2
$ grep FAILED s10-rec-loop.txt
18:00:04 FAILED
18:00:05 FAILED
18:00:05 FAILED
```

Three requests (about 1.5 s) failed. The gap was this short only because the nginx image was already cached on the node; with a slow image pull or slow application start the downtime grows accordingly. The events show the order in a single place, with timestamps:

```bash
$ kubectl get events -n s10-recreate --sort-by=.lastTimestamp -o custom-columns=TIME:.lastTimestamp,REASON:.reason,OBJECT:.involvedObject.name,MESSAGE:.message | grep -E 'TIME|ScalingReplicaSet|Killing|SuccessfulCreate|SuccessfulDelete'
TIME                   REASON              OBJECT                          MESSAGE
2026-10-07T17:59:46Z   ScalingReplicaSet   app-recreate                    Scaled up replica set app-recreate-c5fdd5594 from 0 to 3
2026-10-07T17:59:46Z   SuccessfulCreate    app-recreate-c5fdd5594          Created pod: app-recreate-c5fdd5594-9rrm6
2026-10-07T17:59:46Z   SuccessfulCreate    app-recreate-c5fdd5594          Created pod: app-recreate-c5fdd5594-9pc22
2026-10-07T17:59:46Z   SuccessfulCreate    app-recreate-c5fdd5594          Created pod: app-recreate-c5fdd5594-b2sbg
2026-10-07T18:00:04Z   Killing             app-recreate-c5fdd5594-b2sbg    Stopping container web
2026-10-07T18:00:04Z   Killing             app-recreate-c5fdd5594-9rrm6    Stopping container web
2026-10-07T18:00:04Z   ScalingReplicaSet   app-recreate                    Scaled down replica set app-recreate-c5fdd5594 from 3 to 0
2026-10-07T18:00:04Z   Killing             app-recreate-c5fdd5594-9pc22    Stopping container web
2026-10-07T18:00:04Z   SuccessfulDelete    app-recreate-c5fdd5594          Deleted pod: app-recreate-c5fdd5594-b2sbg
2026-10-07T18:00:04Z   SuccessfulDelete    app-recreate-c5fdd5594          Deleted pod: app-recreate-c5fdd5594-9pc22
2026-10-07T18:00:04Z   SuccessfulDelete    app-recreate-c5fdd5594          Deleted pod: app-recreate-c5fdd5594-9rrm6
2026-10-07T18:00:05Z   SuccessfulCreate    app-recreate-77c5dc4778         Created pod: app-recreate-77c5dc4778-rl649
2026-10-07T18:00:05Z   SuccessfulCreate    app-recreate-77c5dc4778         Created pod: app-recreate-77c5dc4778-2l49x
2026-10-07T18:00:05Z   SuccessfulCreate    app-recreate-77c5dc4778         Created pod: app-recreate-77c5dc4778-p4vwn
2026-10-07T18:00:05Z   ScalingReplicaSet   app-recreate                    Scaled up replica set app-recreate-77c5dc4778 from 0 to 3
$ kubectl describe deployment app-recreate -n s10-recreate | sed -n '/^Events:/,$p'
Events:
  Type    Reason             Age   From                   Message
  ----    ------             ----  ----                   -------
  Normal  ScalingReplicaSet  48s   deployment-controller  Scaled up replica set app-recreate-c5fdd5594 from 0 to 3
  Normal  ScalingReplicaSet  30s   deployment-controller  Scaled down replica set app-recreate-c5fdd5594 from 3 to 0
  Normal  ScalingReplicaSet  29s   deployment-controller  Scaled up replica set app-recreate-77c5dc4778 from 0 to 3
$ kubectl get rs -n s10-recreate -L version
NAME                      DESIRED   CURRENT   READY   AGE   VERSION
app-recreate-77c5dc4778   3         3         3       29s   v2
app-recreate-c5fdd5594    0         0         0       48s   v1
$ kubectl exec -n s10-client curl-client -- curl -s http://app-recreate-service.s10-recreate | grep -oE 'VERSION: v[0-9][^<]*'
VERSION: v2 (UPGRADED)
```

`Scaled down ... from 3 to 0` (18:00:04) comes before `Scaled up ... from 0 to 3` (18:00:05). There is never a moment where v1 and v2 run together, which is why Recreate is used when two versions must not run at the same time (for example a database schema change or a single-writer app).

### Strategy comparison (from what I measured)

| Strategy | How it is done in Kubernetes | Downtime I measured | Both versions live at once? | Rollback | Extra resources |
| --- | --- | --- | --- | --- | --- |
| Rolling Update | `strategy: RollingUpdate`, maxSurge/maxUnavailable | 0 of 90 requests failed | yes, during the rollout | `kubectl rollout undo` (another rolling update) | +1 Pod (maxSurge) |
| Blue-Green | two Deployments, switch the Service selector | 0 of 30 during the switch (one request in the same second after a later switch failed) | no, all traffic flips at once | flip the selector back (instant) | 2x Pods while both run |
| Canary | two Deployments behind one Service, replica ratio | none | yes, by design (~10% / ~50%) | scale the canary to 0 | a few extra Pods |
| Recreate | `strategy: Recreate` | 3 of 50 requests failed (~1.5 s) | never | redeploy the old version (downtime again) | none |

---

## Task 2: Pod Lifecycle

**Phase vs status.** A Pod has only five official **phases**: `Pending`, `Running`, `Succeeded`, `Failed`, `Unknown`. The STATUS column of `kubectl get pods` is a friendlier summary that often shows a container **state** or **reason** instead (`ContainerCreating`, `Completed`, `Error`, `CrashLoopBackOff`, `ImagePullBackOff`, `Terminating`, `Init:0/1`). For each file below I therefore print the phase and the container state with JSONPath as well.

I applied the 12 files from [pod-lifecycle/](pod-lifecycle/) into namespace `s10-lifecycle`, with one `kubectl get pods -w` running in the background for the whole namespace. The per-Pod watch lines below were pulled out of that single log with `grep`.

```bash
$ kubectl create namespace s10-lifecycle
namespace/s10-lifecycle created
$ kubectl get pods -n s10-lifecycle -w | while read -r l; do echo "$(date +%H:%M:%S)  $l"; done > s10-lc-watch-all.txt &
```

### 01-running.yaml: Running

```yaml
apiVersion: v1
kind: Pod
metadata:
  name: lifecycle-running
spec:
  containers:
    - name: nginx
      image: public.ecr.aws/docker/library/nginx:1.27
      ports:
        - containerPort: 80
```

```bash
$ kubectl apply -n s10-lifecycle -f 01-running.yaml
pod/lifecycle-running created
$ kubectl wait -n s10-lifecycle --for=condition=Ready pod/lifecycle-running --timeout=120s
pod/lifecycle-running condition met
$ kubectl get pod lifecycle-running -n s10-lifecycle -o wide
NAME                READY   STATUS    RESTARTS   AGE   IP             NODE       NOMINATED NODE   READINESS GATES
lifecycle-running   1/1     Running   0          0s    10.244.0.112   minikube   <none>           <none>
$ kubectl get pod lifecycle-running -n s10-lifecycle -o jsonpath='{.status.phase}{"\n"}{.status.containerStatuses[0].state}{"\n"}'
Running
{"running":{"startedAt":"2026-10-07T18:00:51Z"}}
$ kubectl describe pod lifecycle-running -n s10-lifecycle | sed -n '/^Conditions:/,/^Volumes:/p;/^Events:/,$p'
Conditions:
  Type                        Status
  PodReadyToStartContainers   True 
  Initialized                 True 
  Ready                       True 
  ContainersReady             True 
  PodScheduled                True 
Volumes:
Events:
  Type    Reason     Age   From               Message
  ----    ------     ----  ----               -------
  Normal  Scheduled  0s    default-scheduler  Successfully assigned s10-lifecycle/lifecycle-running to minikube
  Normal  Pulled     0s    kubelet            spec.containers{nginx}: Container image "public.ecr.aws/docker/library/nginx:1.27" already present on machine and can be accessed by the pod
  Normal  Created    0s    kubelet            spec.containers{nginx}: Container created
  Normal  Started    0s    kubelet            spec.containers{nginx}: Container started
$ kubectl logs lifecycle-running -n s10-lifecycle --tail=3
2026/10/07 18:00:51 [notice] 1#1: start worker process 32
2026/10/07 18:00:51 [notice] 1#1: start worker process 33
2026/10/07 18:00:51 [notice] 1#1: start worker process 34
```

```bash
$ grep -E ' lifecycle-running ' s10-lc-watch-all.txt
23:30:51  lifecycle-running   0/1     Pending   0          0s
23:30:51  lifecycle-running   0/1     Pending   0          0s
23:30:51  lifecycle-running   0/1     ContainerCreating   0          0s
23:30:51  lifecycle-running   0/1     ContainerCreating   0          0s
23:30:51  lifecycle-running   1/1     Running             0          0s
```

**Observed:** `Pending` → `ContainerCreating` → `Running` within a second (the image was already on the node). Phase `Running`, container state `running`, and all five conditions are `True`. `Ready=True` matters because only Ready Pods receive Service traffic.

### 02-pending.yaml: Pending

```yaml
apiVersion: v1
kind: Pod
metadata:
  name: lifecycle-pending
spec:
  containers:
    - name: impossible-resource
      image: public.ecr.aws/docker/library/nginx:1.27
      resources:
        requests:
          cpu: "32"
          memory: "64Gi"
```

```bash
$ kubectl apply -n s10-lifecycle -f 02-pending.yaml
pod/lifecycle-pending created
$ sleep 5; kubectl get pod lifecycle-pending -n s10-lifecycle -o wide
NAME                READY   STATUS    RESTARTS   AGE   IP       NODE     NOMINATED NODE   READINESS GATES
lifecycle-pending   0/1     Pending   0          6s    <none>   <none>   <none>           <none>
$ kubectl get pod lifecycle-pending -n s10-lifecycle -o jsonpath='{.status.phase}{"\n"}{.status.conditions}{"\n"}'
Pending
[{"lastProbeTime":null,"lastTransitionTime":"2026-10-07T18:00:51Z","message":"0/1 nodes are available: 1 Insufficient cpu, 1 Insufficient memory. preemption: 0/1 nodes are available: 1 Preemption is not helpful for scheduling.","observedGeneration":1,"reason":"Unschedulable","status":"False","type":"PodScheduled"}]
$ kubectl describe pod lifecycle-pending -n s10-lifecycle | sed -n '/^Containers:/,/^Conditions:/p' | grep -A3 Requests
    Requests:
      cpu:        32
      memory:     64Gi
    Environment:  <none>
$ kubectl describe pod lifecycle-pending -n s10-lifecycle | sed -n '/^Events:/,$p'
Events:
  Type     Reason            Age              From               Message
  ----     ------            ----             ----               -------
  Warning  FailedScheduling  1s (x4 over 6s)  default-scheduler  0/1 nodes are available: 1 Insufficient cpu, 1 Insufficient memory. preemption: 0/1 nodes are available: 1 Preemption is not helpful for scheduling.
```

```bash
$ grep -E ' lifecycle-pending ' s10-lc-watch-all.txt
23:30:51  lifecycle-pending   0/1     Pending             0          0s
23:30:51  lifecycle-pending   0/1     Pending             0          0s
```

**Observed:** the Pod stays `Pending` with no IP and no node. The scheduler cannot find a node with 32 free CPUs and 64 GiB memory (`Insufficient cpu, Insufficient memory`), so the `PodScheduled` condition is `False` with reason `Unschedulable`. Preemption cannot help either, since no lower-priority Pods would free enough room. The container was never created, so the kubelet never pulled the image.

### 03-succeeded.yaml: Succeeded

```yaml
apiVersion: v1
kind: Pod
metadata:
  name: lifecycle-succeeded
spec:
  restartPolicy: Never
  containers:
    - name: task
      image: public.ecr.aws/docker/library/busybox:1.36
      command: ["sh", "-c", "echo 'Task started'; sleep 5; echo 'Task completed successfully'; exit 0"]
```

```bash
$ kubectl apply -n s10-lifecycle -f 03-succeeded.yaml
pod/lifecycle-succeeded created
$ kubectl get pod lifecycle-succeeded -n s10-lifecycle
NAME                  READY   STATUS              RESTARTS   AGE
lifecycle-succeeded   0/1     ContainerCreating   0          0s
$ sleep 10; kubectl get pod lifecycle-succeeded -n s10-lifecycle
NAME                  READY   STATUS      RESTARTS   AGE
lifecycle-succeeded   0/1     Completed   0          9s
$ kubectl get pod lifecycle-succeeded -n s10-lifecycle -o jsonpath='{.status.phase}{"\n"}{.status.containerStatuses[0].state}{"\n"}'
Succeeded
{"terminated":{"containerID":"containerd://a3bd147886d4b01366eeaf3b39f2bb6329ec76d6279156b55542bfa02d254349","exitCode":0,"finishedAt":"2026-10-07T18:01:37Z","reason":"Completed","startedAt":"2026-10-07T18:01:32Z"}}
$ kubectl describe pod lifecycle-succeeded -n s10-lifecycle | sed -n '/^    State:/,/^    Restart Count/p'
    State:          Terminated
      Reason:       Completed
      Exit Code:    0
      Started:      Wed, 07 Oct 2026 23:31:32 +0530
      Finished:     Wed, 07 Oct 2026 23:31:37 +0530
    Ready:          False
    Restart Count:  0
$ kubectl logs lifecycle-succeeded -n s10-lifecycle
Task started
Task completed successfully
```

```bash
$ grep -E ' lifecycle-succeeded ' s10-lc-watch-all.txt
23:31:31  lifecycle-succeeded     0/1     Pending             0            0s
23:31:31  lifecycle-succeeded     0/1     Pending             0            0s
23:31:31  lifecycle-succeeded     0/1     ContainerCreating   0            0s
23:31:32  lifecycle-succeeded     0/1     ContainerCreating   0            0s
23:31:32  lifecycle-succeeded     1/1     Running             0            0s
23:31:37  lifecycle-succeeded     0/1     Completed           0            5s
23:31:38  lifecycle-succeeded     0/1     Completed           0            7s
```

**Observed:** the container ran for 5 seconds and exited with code 0. Because `restartPolicy: Never`, the kubelet does not restart it. STATUS shows `Completed`, the official phase is `Succeeded`, and the container state is `terminated` with reason `Completed`. This is how Job Pods end.

### 04-failed.yaml: Failed

```yaml
apiVersion: v1
kind: Pod
metadata:
  name: lifecycle-failed
spec:
  restartPolicy: Never
  containers:
    - name: task
      image: public.ecr.aws/docker/library/busybox:1.36
      command: ["sh", "-c", "echo 'Task started'; sleep 5; echo 'Task failed'; exit 1"]
```

```bash
$ kubectl apply -n s10-lifecycle -f 04-failed.yaml
pod/lifecycle-failed created
$ sleep 12; kubectl get pod lifecycle-failed -n s10-lifecycle
NAME               READY   STATUS   RESTARTS   AGE
lifecycle-failed   0/1     Error    0          12s
$ kubectl get pod lifecycle-failed -n s10-lifecycle -o jsonpath='{.status.phase}{"\n"}{.status.containerStatuses[0].state}{"\n"}'
Failed
{"terminated":{"containerID":"containerd://c3386adc0366d2c0c3bfc98253bad73c345eee7a80073084b351fd00e46d9897","exitCode":1,"finishedAt":"2026-10-07T18:01:37Z","reason":"Error","startedAt":"2026-10-07T18:01:32Z"}}
$ kubectl describe pod lifecycle-failed -n s10-lifecycle | sed -n '/^    State:/,/^    Restart Count/p'
    State:          Terminated
      Reason:       Error
      Exit Code:    1
      Started:      Wed, 07 Oct 2026 23:31:32 +0530
      Finished:     Wed, 07 Oct 2026 23:31:37 +0530
    Ready:          False
    Restart Count:  0
$ kubectl describe pod lifecycle-failed -n s10-lifecycle | sed -n '/^Events:/,$p'
Events:
  Type    Reason     Age   From               Message
  ----    ------     ----  ----               -------
  Normal  Scheduled  12s   default-scheduler  Successfully assigned s10-lifecycle/lifecycle-failed to minikube
  Normal  Pulled     12s   kubelet            spec.containers{task}: Container image "public.ecr.aws/docker/library/busybox:1.36" already present on machine and can be accessed by the pod
  Normal  Created    12s   kubelet            spec.containers{task}: Container created
  Normal  Started    12s   kubelet            spec.containers{task}: Container started
$ kubectl logs lifecycle-failed -n s10-lifecycle
Task started
Task failed
```

```bash
$ grep -E ' lifecycle-failed ' s10-lc-watch-all.txt
23:31:31  lifecycle-failed        0/1     Pending             0            0s
23:31:31  lifecycle-failed        0/1     Pending             0            0s
23:31:31  lifecycle-failed        0/1     ContainerCreating   0            0s
23:31:32  lifecycle-failed        0/1     ContainerCreating   0            0s
23:31:32  lifecycle-failed        1/1     Running             0            0s
23:31:37  lifecycle-failed        0/1     Error               0            5s
23:31:38  lifecycle-failed        0/1     Error               0            7s
```

**Observed:** identical to 03 except `exit 1`. With `restartPolicy: Never` a non-zero exit makes the phase `Failed`; STATUS shows `Error` and the container state has `exitCode: 1`. The events look healthy (started normally), so the logs (`Task failed`) and the exit code are where the reason is.

### 05-crashloopbackoff.yaml: CrashLoopBackOff

```yaml
apiVersion: v1
kind: Pod
metadata:
  name: lifecycle-crashloop
spec:
  containers:
    - name: crashing-app
      image: public.ecr.aws/docker/library/busybox:1.36
      command: ["sh", "-c", "echo 'Application started'; sleep 3; echo 'Application crashed'; exit 1"]
```

The default `restartPolicy` is `Always`, so the kubelet restarts the container after each crash, waiting longer every time.

```bash
$ kubectl apply -n s10-lifecycle -f 05-crashloopbackoff.yaml
pod/lifecycle-crashloop created
```

```bash
$ grep -E ' lifecycle-crashloop ' s10-lc-watch-all.txt
23:31:19  lifecycle-crashloop   0/1     Pending             0          0s
23:31:19  lifecycle-crashloop   0/1     Pending             0          0s
23:31:19  lifecycle-crashloop   0/1     ContainerCreating   0          0s
23:31:19  lifecycle-crashloop   0/1     ContainerCreating   0          0s
23:31:19  lifecycle-crashloop   1/1     Running             0          0s
23:31:23  lifecycle-crashloop   0/1     Error               0          4s
23:31:23  lifecycle-crashloop   1/1     Running             1 (1s ago)   4s
23:31:27  lifecycle-crashloop   0/1     Error               1 (5s ago)   8s
23:31:40  lifecycle-crashloop     0/1     CrashLoopBackOff    1 (14s ago)   21s
23:31:40  lifecycle-crashloop     1/1     Running             2 (14s ago)   21s
23:31:43  lifecycle-crashloop     0/1     Error               2 (17s ago)   24s
23:32:09  lifecycle-crashloop     0/1     CrashLoopBackOff    2 (27s ago)   51s
23:32:09  lifecycle-crashloop     1/1     Running             3 (27s ago)   51s
23:32:13  lifecycle-crashloop     0/1     Error               3 (30s ago)   54s
23:33:01  lifecycle-crashloop         0/1     CrashLoopBackOff    3 (49s ago)   102s
23:33:01  lifecycle-crashloop         1/1     Running             4 (49s ago)   102s
23:33:05  lifecycle-crashloop         0/1     Error               4 (53s ago)   106s
23:34:18  lifecycle-crashloop         0/1     CrashLoopBackOff    4 (74s ago)   2m59s
23:34:27  lifecycle-crashloop         1/1     Running             5 (83s ago)   3m8s
23:34:30  lifecycle-crashloop         0/1     Error               5 (86s ago)   3m11s
```

```bash
$ kubectl get pod lifecycle-crashloop -n s10-lifecycle
NAME                  READY   STATUS   RESTARTS      AGE
lifecycle-crashloop   0/1     Error    3 (51s ago)   75s
$ kubectl get pod lifecycle-crashloop -n s10-lifecycle -o jsonpath='{.status.phase}{"\n"}{.status.containerStatuses[0].state}{"\n"}{.status.containerStatuses[0].lastState}{"\n"}'
Running
{"terminated":{"containerID":"containerd://4319402141385f80d5502e847d571ae1b585dd60bc22ab0b92a51b065905f6a1","exitCode":1,"finishedAt":"2026-10-07T18:02:12Z","reason":"Error","startedAt":"2026-10-07T18:02:10Z"}}
{"terminated":{"containerID":"containerd://506e0951f68e4dffd1cc0b574eba2932d1b8d951234073608ab31c6513e5ee9b","exitCode":1,"finishedAt":"2026-10-07T18:01:43Z","reason":"Error","startedAt":"2026-10-07T18:01:40Z"}}
$ kubectl describe pod lifecycle-crashloop -n s10-lifecycle | sed -n '/^    State:/,/^    Ready:/p;/^    Restart Count/p'
    State:          Terminated
      Reason:       Error
      Exit Code:    1
      Started:      Wed, 07 Oct 2026 23:32:10 +0530
      Finished:     Wed, 07 Oct 2026 23:32:12 +0530
    Last State:     Terminated
      Reason:       Error
      Exit Code:    1
      Started:      Wed, 07 Oct 2026 23:31:40 +0530
      Finished:     Wed, 07 Oct 2026 23:31:43 +0530
    Ready:          False
    Restart Count:  3
$ kubectl describe pod lifecycle-crashloop -n s10-lifecycle | sed -n '/^Events:/,$p'
Events:
  Type     Reason     Age                From               Message
  ----     ------     ----               ----               -------
  Normal   Scheduled  75s                default-scheduler  Successfully assigned s10-lifecycle/lifecycle-crashloop to minikube
  Normal   Pulled     24s (x4 over 75s)  kubelet            spec.containers{crashing-app}: Container image "public.ecr.aws/docker/library/busybox:1.36" already present on machine and can be accessed by the pod
  Normal   Created    24s (x4 over 75s)  kubelet            spec.containers{crashing-app}: Container created
  Normal   Started    24s (x4 over 75s)  kubelet            spec.containers{crashing-app}: Container started
  Warning  BackOff    21s (x3 over 67s)  kubelet            spec.containers{crashing-app}: Back-off restarting failed container crashing-app in pod lifecycle-crashloop_s10-lifecycle(c8cba00c-0524-468c-a009-838b3c3312f6)
$ kubectl logs lifecycle-crashloop -n s10-lifecycle
Application started
Application crashed
```

```bash
$ kubectl get pod lifecycle-crashloop -n s10-lifecycle
NAME                  READY   STATUS             RESTARTS      AGE
lifecycle-crashloop   0/1     CrashLoopBackOff   4 (78s ago)   3m3s
$ kubectl logs lifecycle-crashloop -n s10-lifecycle --previous
Application started
Application crashed
```

**Observed:** the cycle is `Running` → `Error` (exit 1 after 3 s) → `CrashLoopBackOff` → `Running` again. The waits between restarts grow: about 0 s, 13 s, 26 s, 48 s, 82 s (the kubelet's back-off doubles: 10 s, 20 s, 40 s, 80 s ... up to 5 minutes). The phase stays `Running`, because the Pod is still "alive" and being restarted; only the container keeps dying. `kubectl logs --previous` shows the output of the last crashed container. My first `--previous` attempt (in the earlier block) printed "unable to retrieve container logs". At that moment the current container had also just crashed, and the older dead container that `--previous` pointed to had most likely already been cleaned up by the kubelet. Asking again after the next restart worked.

### 06-imagepullbackoff.yaml: ImagePullBackOff

```yaml
apiVersion: v1
kind: Pod
metadata:
  name: lifecycle-image-error
spec:
  containers:
    - name: broken-image
      image: jakwehrgkaejw:kahsdfgkhj
```

```bash
$ kubectl apply -n s10-lifecycle -f 06-imagepullbackoff.yaml
pod/lifecycle-image-error created
$ sleep 25; kubectl get pod lifecycle-image-error -n s10-lifecycle
NAME                    READY   STATUS             RESTARTS   AGE
lifecycle-image-error   0/1     ImagePullBackOff   0          25s
$ kubectl get pod lifecycle-image-error -n s10-lifecycle -o jsonpath='{.status.phase}{"\n"}{.status.containerStatuses[0].state}{"\n"}'
Pending
{"waiting":{"message":"Back-off pulling image \"jakwehrgkaejw:kahsdfgkhj\": ErrImagePull: failed to pull and unpack image \"docker.io/library/jakwehrgkaejw:kahsdfgkhj\": failed to resolve reference \"docker.io/library/jakwehrgkaejw:kahsdfgkhj\": pull access denied, repository does not exist or may require authorization: server message: insufficient_scope: authorization failed","reason":"ImagePullBackOff"}}
$ kubectl describe pod lifecycle-image-error -n s10-lifecycle | sed -n '/^Events:/,$p' | cut -c1-300
Events:
  Type     Reason     Age                From               Message
  ----     ------     ----               ----               -------
  Normal   Scheduled  25s                default-scheduler  Successfully assigned s10-lifecycle/lifecycle-image-error to minikube
  Normal   BackOff    23s                kubelet            spec.containers{broken-image}: Back-off pulling image "jakwehrgkaejw:kahsdfgkhj"
  Warning  Failed     23s                kubelet            spec.containers{broken-image}: Error: ImagePullBackOff
  Normal   Pulling    11s (x2 over 25s)  kubelet            spec.containers{broken-image}: Pulling image "jakwehrgkaejw:kahsdfgkhj"
  Warning  Failed     10s (x2 over 23s)  kubelet            spec.containers{broken-image}: Failed to pull image "jakwehrgkaejw:kahsdfgkhj": failed to pull and unpack image "docker.io/library/jakwehrgkaejw:kahsdfgkhj": failed to resolve reference "docker.io/library/jakwehrgkaejw:kahsdfgkhj": pull acc
  Warning  Failed     10s (x2 over 23s)  kubelet            spec.containers{broken-image}: Error: ErrImagePull
```

```bash
$ grep -E ' lifecycle-image-error ' s10-lc-watch-all.txt
23:31:31  lifecycle-image-error   0/1     Pending             0            0s
23:31:31  lifecycle-image-error   0/1     Pending             0            0s
23:31:31  lifecycle-image-error   0/1     ContainerCreating   0            0s
23:31:32  lifecycle-image-error   0/1     ContainerCreating   0            0s
23:31:34  lifecycle-image-error   0/1     ErrImagePull        0            2s
23:31:46  lifecycle-image-error   0/1     ImagePullBackOff    0             14s
23:32:01  lifecycle-image-error   0/1     ErrImagePull        0             29s
23:32:15  lifecycle-image-error   0/1     ImagePullBackOff    0             43s
...
```

**Observed:** the phase is `Pending` (the container never started), and the status alternates between `ErrImagePull` (a pull attempt just failed) and `ImagePullBackOff` (waiting before the next attempt, with growing delays). The full reason is in the container state: `docker.io/library/jakwehrgkaejw:kahsdfgkhj` → `pull access denied, repository does not exist or may require authorization`. So the real cause is a repository that does not exist, not the Docker Hub rate limit.

### 07-readiness.yaml: Readiness probe

```yaml
apiVersion: v1
kind: Pod
metadata:
  name: lifecycle-readiness
spec:
  containers:
    - name: nginx
      image: public.ecr.aws/docker/library/nginx:1.27
      readinessProbe:
        httpGet:
          path: /
          port: 80
        initialDelaySeconds: 5
        periodSeconds: 5
```

```bash
$ kubectl apply -n s10-lifecycle -f 07-readiness.yaml
pod/lifecycle-readiness created
```

```bash
$ grep -E ' lifecycle-readiness ' s10-lc-watch-all.txt
23:31:19  lifecycle-readiness   0/1     Pending             0          0s
23:31:19  lifecycle-readiness   0/1     Pending             0          0s
23:31:19  lifecycle-readiness   0/1     ContainerCreating   0          0s
23:31:19  lifecycle-readiness   0/1     ContainerCreating   0          0s
...
```

```bash
$ kubectl get pod lifecycle-readiness -n s10-lifecycle
NAME                  READY   STATUS    RESTARTS   AGE
lifecycle-readiness   1/1     Running   0          15s
$ kubectl describe pod lifecycle-readiness -n s10-lifecycle | grep -E '^ +Readiness:'
    Readiness:      http-get http://:80/ delay=5s timeout=1s period=5s successThreshold=1 failureThreshold=3
$ kubectl describe pod lifecycle-readiness -n s10-lifecycle | sed -n '/^Conditions:/,/^Volumes:/p'
Conditions:
  Type                        Status
  PodReadyToStartContainers   True 
  Initialized                 True 
  Ready                       True 
  ContainersReady             True 
  PodScheduled                True 
Volumes:
$ kubectl describe pod lifecycle-readiness -n s10-lifecycle | sed -n '/^Events:/,$p'
Events:
  Type    Reason     Age   From               Message
  ----    ------     ----  ----               -------
  Normal  Scheduled  15s   default-scheduler  Successfully assigned s10-lifecycle/lifecycle-readiness to minikube
  Normal  Pulled     15s   kubelet            spec.containers{nginx}: Container image "public.ecr.aws/docker/library/nginx:1.27" already present on machine and can be accessed by the pod
  Normal  Created    15s   kubelet            spec.containers{nginx}: Container created
  Normal  Started    14s   kubelet            spec.containers{nginx}: Container started
```

**Observed:** for the first ~6 seconds the Pod was `Running` but `0/1`: the container had started, but the readiness probe only begins after `initialDelaySeconds: 5`. After the first successful probe it became `1/1`. **Running is not the same as Ready.**

To see a readiness failure I deleted nginx's index page, so `GET /` returns 403:

```bash
$ kubectl exec lifecycle-readiness -n s10-lifecycle -- rm /usr/share/nginx/html/index.html
$ sleep 18; kubectl get pod lifecycle-readiness -n s10-lifecycle
NAME                  READY   STATUS    RESTARTS   AGE
lifecycle-readiness   0/1     Running   0          3m27s
$ kubectl describe pod lifecycle-readiness -n s10-lifecycle | grep -E '^    (Ready|Restart Count):|Readiness probe failed'
    Ready:          False
    Restart Count:  0
  Warning  Unhealthy  2s (x5 over 17s)  kubelet            spec.containers{nginx}: Readiness probe failed: HTTP probe failed with statuscode: 403
$ kubectl exec lifecycle-readiness -n s10-lifecycle -- sh -c 'echo ok > /usr/share/nginx/html/index.html'
$ sleep 8; kubectl get pod lifecycle-readiness -n s10-lifecycle
NAME                  READY   STATUS    RESTARTS   AGE
lifecycle-readiness   1/1     Running   0          3m36s
```

The Pod went back to `0/1 Running` with `Restart Count: 0`. A failing readiness probe never restarts the container; it only marks the Pod not ready, which removes it from Service endpoints. When I restored the page it became Ready again by itself.

### 08-liveness.yaml: Liveness probe

```yaml
apiVersion: v1
kind: Pod
metadata:
  name: lifecycle-liveness
spec:
  containers:
    - name: app
      image: public.ecr.aws/docker/library/busybox:1.36
      command: ["sh", "-c", "echo 'App started'; touch /tmp/healthy; sleep 20; rm /tmp/healthy; echo 'Health file removed'; sleep 300"]
      livenessProbe:
        exec:
          command: ["sh", "-c", "test -f /tmp/healthy"]
        initialDelaySeconds: 5
        periodSeconds: 5
        failureThreshold: 2
```

```bash
$ kubectl apply -n s10-lifecycle -f 08-liveness.yaml
pod/lifecycle-liveness created
```

```bash
$ grep -E ' lifecycle-liveness ' s10-lc-watch-all.txt
23:31:19  lifecycle-liveness   0/1     Pending             0          0s
23:31:19  lifecycle-liveness    0/1     Pending             0          0s
23:31:19  lifecycle-liveness    0/1     ContainerCreating   0          0s
23:31:19  lifecycle-liveness    0/1     ContainerCreating   0          0s
23:31:19  lifecycle-liveness    1/1     Running             0          1s
23:32:19  lifecycle-liveness      1/1     Running             1 (0s ago)    60s
23:33:19  lifecycle-liveness          1/1     Running             2 (0s ago)    2m
23:34:18  lifecycle-liveness          1/1     Running             3 (0s ago)    2m59s
```

```bash
$ kubectl get pod lifecycle-liveness -n s10-lifecycle
NAME                 READY   STATUS    RESTARTS      AGE
lifecycle-liveness   1/1     Running   1 (20s ago)   80s
$ kubectl describe pod lifecycle-liveness -n s10-lifecycle | grep -E '^ +Liveness:|^    Restart Count|^    Last State|^      Reason|^      Exit Code'
    Last State:     Terminated
      Reason:       Error
      Exit Code:    137
    Restart Count:  1
    Liveness:       exec [sh -c test -f /tmp/healthy] delay=5s timeout=1s period=5s successThreshold=1 failureThreshold=2
$ kubectl describe pod lifecycle-liveness -n s10-lifecycle | sed -n '/^Events:/,$p'
Events:
  Type     Reason     Age                From               Message
  ----     ------     ----               ----               -------
  Normal   Scheduled  80s                default-scheduler  Successfully assigned s10-lifecycle/lifecycle-liveness to minikube
  Warning  Unhealthy  50s (x2 over 55s)  kubelet            spec.containers{app}: Liveness probe failed:
  Normal   Killing    50s                kubelet            spec.containers{app}: Container app failed liveness probe, will be restarted
  Normal   Pulled     20s (x2 over 80s)  kubelet            spec.containers{app}: Container image "public.ecr.aws/docker/library/busybox:1.36" already present on machine and can be accessed by the pod
  Normal   Created    20s (x2 over 80s)  kubelet            spec.containers{app}: Container created
  Normal   Started    20s (x2 over 79s)  kubelet            spec.containers{app}: Container started
$ kubectl logs lifecycle-liveness -n s10-lifecycle --previous
App started
Health file removed
```

**Observed:** the app deletes `/tmp/healthy` after 20 s. The liveness probe then fails twice (`failureThreshold: 2`, every 5 s), the kubelet logs `Container app failed liveness probe, will be restarted`, and the container is restarted. Unlike readiness, **liveness failures restart the container**. `kubectl logs --previous` shows the old container got as far as `Health file removed`.

One detail I did not expect: the kill happened ~30 s after the start, but the new container only started at 60 s (the RESTARTS column ticks once a minute). The last state is `Exit Code: 137` (SIGKILL). The container's PID 1 is `sh`, which ignores SIGTERM, so the kubelet had to wait out the default 30 s `terminationGracePeriodSeconds` before it could force-kill it. The full cycle is therefore 20 s healthy + ~10 s of failed probes + 30 s grace ≈ 60 s.

### 09-startup.yaml: Startup probe

```yaml
apiVersion: v1
kind: Pod
metadata:
  name: lifecycle-startup
spec:
  containers:
    - name: slow-app
      image: public.ecr.aws/docker/library/busybox:1.36
      command: ["sh", "-c", "echo 'Application starting...'; sleep 30; touch /tmp/started; echo 'Application started'; sleep 300"]
      startupProbe:
        exec:
          command: ["sh", "-c", "test -f /tmp/started"]
        periodSeconds: 5
        failureThreshold: 10
```

```bash
$ kubectl apply -n s10-lifecycle -f 09-startup.yaml
pod/lifecycle-startup created
```

```bash
$ grep -E ' lifecycle-startup ' s10-lc-watch-all.txt
23:31:19  lifecycle-startup    0/1     Pending             0          0s
23:31:19  lifecycle-startup    0/1     Pending             0          0s
23:31:19  lifecycle-startup     0/1     ContainerCreating   0          0s
23:31:19  lifecycle-startup     0/1     ContainerCreating   0          0s
23:31:19  lifecycle-startup     0/1     Running             0          1s
23:31:54  lifecycle-startup       0/1     Running             0             35s
23:31:54  lifecycle-startup       1/1     Running             0             35s
```

```bash
$ kubectl get pod lifecycle-startup -n s10-lifecycle
NAME                READY   STATUS    RESTARTS   AGE
lifecycle-startup   1/1     Running   0          50s
$ kubectl describe pod lifecycle-startup -n s10-lifecycle | grep -E '^ +Startup:|^    Restart Count|^    Ready:'
    Ready:          True
    Restart Count:  0
    Startup:        exec [sh -c test -f /tmp/started] delay=0s timeout=1s period=5s successThreshold=1 failureThreshold=10
$ kubectl describe pod lifecycle-startup -n s10-lifecycle | sed -n '/^Events:/,$p'
Events:
  Type     Reason     Age                From               Message
  ----     ------     ----               ----               -------
  Normal   Scheduled  50s                default-scheduler  Successfully assigned s10-lifecycle/lifecycle-startup to minikube
  Normal   Pulled     50s                kubelet            spec.containers{slow-app}: Container image "public.ecr.aws/docker/library/busybox:1.36" already present on machine and can be accessed by the pod
  Normal   Created    50s                kubelet            spec.containers{slow-app}: Container created
  Normal   Started    49s                kubelet            spec.containers{slow-app}: Container started
  Warning  Unhealthy  20s (x6 over 45s)  kubelet            spec.containers{slow-app}: Startup probe failed:
$ kubectl logs lifecycle-startup -n s10-lifecycle
Application starting...
Application started
```

**Observed:** the app needs 30 s to create `/tmp/started`. The startup probe failed 6 times (`Startup probe failed`, every 5 s), which is fine because it is allowed `10 x 5 s = 50 s`. At 35 s it succeeded and the Pod became `1/1` with **0 restarts**. While a startup probe is running, liveness and readiness probes are paused. This is how slow-starting apps are protected from being killed by an impatient liveness probe. With `failureThreshold: 5` (25 s) this Pod would have been restarted in a loop.

### 10-init-container.yaml: Init container

```yaml
apiVersion: v1
kind: Pod
metadata:
  name: lifecycle-init
spec:
  initContainers:
    - name: setup
      image: public.ecr.aws/docker/library/busybox:1.36
      command: ["sh", "-c", "echo 'Init container running'; sleep 10; echo 'Init complete'"]
  containers:
    - name: app
      image: public.ecr.aws/docker/library/nginx:1.27
```

```bash
$ kubectl apply -n s10-lifecycle -f 10-init-container.yaml
pod/lifecycle-init created
$ sleep 3; kubectl get pod lifecycle-init -n s10-lifecycle
NAME             READY   STATUS     RESTARTS   AGE
lifecycle-init   0/1     Init:0/1   0          3s
$ kubectl get pod lifecycle-init -n s10-lifecycle -o jsonpath='{.status.initContainerStatuses[0].state}{"\n"}{.status.containerStatuses[0].state}{"\n"}'
{"running":{"startedAt":"2026-10-07T18:02:08Z"}}
{"waiting":{"reason":"PodInitializing"}}
```

```bash
$ grep -E ' lifecycle-init ' s10-lc-watch-all.txt
23:32:08  lifecycle-init          0/1     Pending             0             0s
23:32:08  lifecycle-init          0/1     Pending             0             0s
23:32:08  lifecycle-init          0/1     Init:0/1            0             0s
23:32:08  lifecycle-init          0/1     Init:0/1            0             0s
23:32:08  lifecycle-init          0/1     Init:0/1            0             0s
23:32:19  lifecycle-init          0/1     PodInitializing     0             11s
23:32:19  lifecycle-init          1/1     Running             0             11s
```

```bash
$ sleep 15; kubectl get pod lifecycle-init -n s10-lifecycle
NAME             READY   STATUS    RESTARTS   AGE
lifecycle-init   1/1     Running   0          18s
$ kubectl describe pod lifecycle-init -n s10-lifecycle | sed -n '/^Init Containers:/,/^Containers:/p' | grep -E '^  setup:|State|Reason|Exit Code|Started|Finished'
  setup:
    State:          Terminated
      Reason:       Completed
      Exit Code:    0
      Started:      Wed, 07 Oct 2026 23:32:08 +0530
      Finished:     Wed, 07 Oct 2026 23:32:18 +0530
$ kubectl describe pod lifecycle-init -n s10-lifecycle | sed -n '/^Events:/,$p'
Events:
  Type    Reason     Age   From               Message
  ----    ------     ----  ----               -------
  Normal  Scheduled  18s   default-scheduler  Successfully assigned s10-lifecycle/lifecycle-init to minikube
  Normal  Pulled     18s   kubelet            spec.initContainers{setup}: Container image "public.ecr.aws/docker/library/busybox:1.36" already present on machine and can be accessed by the pod
  Normal  Created    18s   kubelet            spec.initContainers{setup}: Container created
  Normal  Started    18s   kubelet            spec.initContainers{setup}: Container started
  Normal  Pulled     7s    kubelet            spec.containers{app}: Container image "public.ecr.aws/docker/library/nginx:1.27" already present on machine and can be accessed by the pod
  Normal  Created    7s    kubelet            spec.containers{app}: Container created
  Normal  Started    7s    kubelet            spec.containers{app}: Container started
$ kubectl logs lifecycle-init -n s10-lifecycle -c setup
Init container running
Init complete
```

**Observed:** STATUS `Init:0/1` means 0 of 1 init containers finished. While `setup` was running, the main container `app` was `waiting` with reason `PodInitializing`. The init container ran from 23:32:08 to 23:32:18 (its `sleep 10`), exited 0 (`Completed`), and only then did the kubelet start nginx (the events show `app` started 11 s after `setup`). Init containers run one after another, each to completion, before any app container starts.

### 11-multi-container.yaml: Multi-container Pod (sidecar)

```yaml
apiVersion: v1
kind: Pod
metadata:
  name: lifecycle-multi-container
spec:
  containers:
    - name: app
      image: public.ecr.aws/docker/library/nginx:1.27
    - name: sidecar
      image: public.ecr.aws/docker/library/busybox:1.36
      command: ["sh", "-c", "while true; do echo 'Sidecar is running'; sleep 10; done"]
```

```bash
$ kubectl apply -n s10-lifecycle -f 11-multi-container.yaml
pod/lifecycle-multi-container created
$ kubectl wait -n s10-lifecycle --for=condition=Ready pod/lifecycle-multi-container --timeout=120s
pod/lifecycle-multi-container condition met
$ kubectl get pod lifecycle-multi-container -n s10-lifecycle
NAME                        READY   STATUS    RESTARTS   AGE
lifecycle-multi-container   2/2     Running   0          1s
$ kubectl get pod lifecycle-multi-container -n s10-lifecycle -o jsonpath='{range .status.containerStatuses[*]}{.name}{"\t"}{.ready}{"\t"}{.state}{"\n"}{end}'
app	true	{"running":{"startedAt":"2026-10-07T18:02:27Z"}}
sidecar	true	{"running":{"startedAt":"2026-10-07T18:02:27Z"}}
$ kubectl describe pod lifecycle-multi-container -n s10-lifecycle | sed -n '/^Events:/,$p'
Events:
  Type    Reason     Age   From               Message
  ----    ------     ----  ----               -------
  Normal  Scheduled  1s    default-scheduler  Successfully assigned s10-lifecycle/lifecycle-multi-container to minikube
  Normal  Pulled     0s    kubelet            spec.containers{app}: Container image "public.ecr.aws/docker/library/nginx:1.27" already present on machine and can be accessed by the pod
  Normal  Created    0s    kubelet            spec.containers{app}: Container created
  Normal  Started    0s    kubelet            spec.containers{app}: Container started
  Normal  Pulled     0s    kubelet            spec.containers{sidecar}: Container image "public.ecr.aws/docker/library/busybox:1.36" already present on machine and can be accessed by the pod
  Normal  Created    0s    kubelet            spec.containers{sidecar}: Container created
  Normal  Started    0s    kubelet            spec.containers{sidecar}: Container started
$ sleep 12; kubectl logs lifecycle-multi-container -n s10-lifecycle -c sidecar
Sidecar is running
Sidecar is running
$ kubectl logs lifecycle-multi-container -n s10-lifecycle -c app --tail=2
2026/10/07 18:02:27 [notice] 1#1: start worker process 33
2026/10/07 18:02:27 [notice] 1#1: start worker process 34
$ kubectl exec lifecycle-multi-container -n s10-lifecycle -c sidecar -- wget -qO- http://localhost:80 | grep title
<title>Welcome to nginx!</title>
```

```bash
$ grep -E ' lifecycle-multi-container ' s10-lc-watch-all.txt
23:32:26  lifecycle-multi-container   0/2     Pending             0             0s
23:32:26  lifecycle-multi-container   0/2     Pending             0             0s
23:32:26  lifecycle-multi-container   0/2     ContainerCreating   0             0s
23:32:27  lifecycle-multi-container   0/2     ContainerCreating   0             1s
23:32:27  lifecycle-multi-container   2/2     Running             0             1s
```

**Observed:** READY shows `2/2` because the Pod has two containers and both must be ready for the Pod to be Ready. Each container has its own logs (`-c app`, `-c sidecar`). They share the network namespace: from the sidecar, `wget http://localhost:80` reached nginx running in the other container.

### 12-termination.yaml: Graceful termination

```yaml
apiVersion: v1
kind: Pod
metadata:
  name: lifecycle-termination
spec:
  terminationGracePeriodSeconds: 20
  containers:
    - name: graceful-app
      image: public.ecr.aws/docker/library/busybox:1.36
      command:
        - sh
        - -c
        - |
          trap 'echo "SIGTERM received; cleaning up..."; sleep 10; echo "Cleanup complete"; exit 0' TERM
          echo "Application running"
          while true; do sleep 2; done
```

First run, timing the delete:

```bash
$ kubectl apply -n s10-lifecycle -f 12-termination.yaml
pod/lifecycle-termination created
$ kubectl wait -n s10-lifecycle --for=condition=Ready pod/lifecycle-termination --timeout=120s
pod/lifecycle-termination condition met
$ kubectl get pod lifecycle-termination -n s10-lifecycle -o jsonpath='{.spec.terminationGracePeriodSeconds}{"\n"}'
20
$ time kubectl delete pod lifecycle-termination -n s10-lifecycle
pod "lifecycle-termination" deleted from s10-lifecycle namespace

real	0m10.460s
user	0m0.032s
sys	0m0.016s
```

```bash
$ grep -E ' lifecycle-termination ' s10-lc-watch-all.txt | head -12
23:32:49  lifecycle-termination       0/1     Pending             0             0s
23:32:49  lifecycle-termination       0/1     Pending             0             0s
23:32:49  lifecycle-termination       0/1     ContainerCreating   0             0s
23:32:49  lifecycle-termination       0/1     ContainerCreating   0             0s
23:32:49  lifecycle-termination       1/1     Running             0             0s
23:32:52  lifecycle-termination       1/1     Terminating         0             3s
23:32:52  lifecycle-termination       1/1     Terminating         0             3s
...
```

`kubectl delete` took 10.5 s, not 20 s and not instantly. To see the log lines written during shutdown, I first tried a background `kubectl logs -f`, but it stopped after the first line with `failed to create fsnotify watcher: too many open files` (the shared node had run out of inotify watchers). So I ran the Pod again and polled the status and last log line once per second:

```bash
$ kubectl apply -n s10-lifecycle -f 12-termination.yaml
pod/lifecycle-termination created
$ kubectl wait -n s10-lifecycle --for=condition=Ready pod/lifecycle-termination --timeout=60s
pod/lifecycle-termination condition met
$ kubectl delete pod lifecycle-termination -n s10-lifecycle --wait=false
pod "lifecycle-termination" deleted from s10-lifecycle namespace
$ for i in $(seq 1 14); do echo "[$(date +%T)] $(kubectl get pod lifecycle-termination -n s10-lifecycle --no-headers 2>&1 | awk '{print $3}') | last log line: $(kubectl logs lifecycle-termination -n s10-lifecycle --tail=1 2>&1)"; sleep 1; done
[23:33:50] Terminating | last log line: Application running
[23:33:51] Terminating | last log line: SIGTERM received; cleaning up...
[23:33:52] Terminating | last log line: SIGTERM received; cleaning up...
[23:33:53] Terminating | last log line: SIGTERM received; cleaning up...
[23:33:55] Terminating | last log line: SIGTERM received; cleaning up...
[23:33:56] Terminating | last log line: SIGTERM received; cleaning up...
[23:33:57] Terminating | last log line: SIGTERM received; cleaning up...
[23:33:58] Terminating | last log line: SIGTERM received; cleaning up...
[23:33:59] Terminating | last log line: SIGTERM received; cleaning up...
[23:34:00] Terminating | last log line: SIGTERM received; cleaning up...
[23:34:01] Completed | last log line: Cleanup complete
[23:34:02] server | last log line: error: error from server (NotFound): pods "lifecycle-termination" not found in namespace "s10-lifecycle"
[23:34:03] server | last log line: error: error from server (NotFound): pods "lifecycle-termination" not found in namespace "s10-lifecycle"
[23:34:04] server | last log line: error: error from server (NotFound): pods "lifecycle-termination" not found in namespace "s10-lifecycle"
```

**Observed:** on `kubectl delete` the Pod turned `Terminating` and the kubelet sent SIGTERM. The shell's `trap` printed `SIGTERM received; cleaning up...`, did its 10 s of "cleanup", printed `Cleanup complete` and exited 0 (`Completed`), after which the Pod object was removed. Because the app finished cleanup within `terminationGracePeriodSeconds: 20`, it was never SIGKILLed. Compare with the liveness Pod above, whose shell ignored SIGTERM and was killed only after the 30 s default grace period.

### Summary of all lifecycle Pods

```bash
$ kubectl get pods -n s10-lifecycle
NAME                        READY   STATUS             RESTARTS       AGE
lifecycle-crashloop         0/1     Error              5 (116s ago)   3m41s
lifecycle-failed            0/1     Error              0              3m28s
lifecycle-image-error       0/1     ImagePullBackOff   0              3m28s
lifecycle-init              1/1     Running            0              2m52s
lifecycle-liveness          1/1     Running            3 (42s ago)    3m41s
lifecycle-multi-container   2/2     Running            0              2m34s
lifecycle-pending           0/1     Pending            0              4m9s
lifecycle-readiness         1/1     Running            0              3m41s
lifecycle-running           1/1     Running            0              4m9s
lifecycle-startup           1/1     Running            0              3m41s
lifecycle-succeeded         0/1     Completed          0              3m28s
$ kubectl get pods -n s10-lifecycle -o custom-columns=POD:.metadata.name,PHASE:.status.phase,READY:.status.containerStatuses[*].ready,RESTARTS:.status.containerStatuses[*].restartCount
POD                         PHASE       READY       RESTARTS
lifecycle-crashloop         Running     false       5
lifecycle-failed            Failed      false       0
lifecycle-image-error       Pending     false       0
lifecycle-init              Running     true        0
lifecycle-liveness          Running     true        3
lifecycle-multi-container   Running     true,true   0,0
lifecycle-pending           Pending     <none>      <none>
lifecycle-readiness         Running     true        0
lifecycle-running           Running     true        0
lifecycle-startup           Running     true        0
lifecycle-succeeded         Succeeded   false       0
```

(`lifecycle-termination` is missing because it was deleted as part of its own test.)

| File | STATUS seen | Phase | What caused it |
| --- | --- | --- | --- |
| 01-running | Running 1/1 | Running | container started, all conditions True |
| 02-pending | Pending | Pending | requests (32 CPU / 64Gi) fit no node: FailedScheduling |
| 03-succeeded | Completed | Succeeded | exit 0 with restartPolicy Never |
| 04-failed | Error | Failed | exit 1 with restartPolicy Never |
| 05-crashloopbackoff | Error / CrashLoopBackOff | Running | exit 1 with restartPolicy Always, exponential back-off |
| 06-imagepullbackoff | ErrImagePull / ImagePullBackOff | Pending | repository does not exist |
| 07-readiness | Running 0/1 → 1/1 | Running | readiness gates traffic, never restarts |
| 08-liveness | Running, RESTARTS climbing | Running | liveness failure restarts the container (exit 137) |
| 09-startup | Running 0/1 → 1/1, 0 restarts | Running | startup probe gave the slow app 50 s |
| 10-init-container | Init:0/1 → PodInitializing → Running | Pending → Running | init container must finish first |
| 11-multi-container | Running 2/2 | Running | app + sidecar share network and lifecycle |
| 12-termination | Terminating → Completed | Running → Succeeded | SIGTERM handled within the grace period |

---

### Basic Pod, ReplicaSet, Deployment, DaemonSet and StatefulSet examples

The course folder also has single-object examples. I ran them in namespace `s10-objects`.

```bash
$ kubectl create namespace s10-objects
namespace/s10-objects created
$ kubectl apply -n s10-objects -f core-objects/pod.yaml
pod/yatri-demo-pod created
$ kubectl apply -n s10-objects -f core-objects/replicaset.yaml
replicaset.apps/yatri-backend-rs created
$ kubectl apply -n s10-objects -f core-objects/daemonset.yaml
daemonset.apps/node-logging-agent created
$ kubectl apply -n s10-objects -f core-objects/statefulset.yaml
service/web-sts created
statefulset.apps/web-sts created
$ kubectl wait -n s10-objects --for=condition=Ready pod --all --timeout=180s
pod/node-logging-agent-zr6st condition met
pod/web-sts-0 condition met
pod/yatri-backend-rs-5cr5b condition met
pod/yatri-backend-rs-p5wsp condition met
pod/yatri-backend-rs-ts48x condition met
pod/yatri-demo-pod condition met
$ kubectl get pods -n s10-objects -o wide
NAME                       READY   STATUS    RESTARTS   AGE   IP             NODE       NOMINATED NODE   READINESS GATES
node-logging-agent-zr6st   1/1     Running   0          6s    10.244.0.156   minikube   <none>           <none>
web-sts-0                  1/1     Running   0          6s    10.244.0.157   minikube   <none>           <none>
web-sts-1                  1/1     Running   0          6s    10.244.0.158   minikube   <none>           <none>
yatri-backend-rs-5cr5b     1/1     Running   0          6s    10.244.0.154   minikube   <none>           <none>
yatri-backend-rs-p5wsp     1/1     Running   0          6s    10.244.0.155   minikube   <none>           <none>
yatri-backend-rs-ts48x     1/1     Running   0          6s    10.244.0.153   minikube   <none>           <none>
yatri-demo-pod             1/1     Running   0          7s    10.244.0.152   minikube   <none>           <none>
```

#### Pod ([core-objects/pod.yaml](core-objects/pod.yaml))

```bash
$ kubectl get pod yatri-demo-pod -n s10-objects --show-labels
NAME             READY   STATUS    RESTARTS   AGE   LABELS
yatri-demo-pod   1/1     Running   0          21s   app=yatri-demo,tier=frontend
$ kubectl describe pod yatri-demo-pod -n s10-objects | grep -E '^QoS Class|^Controlled By|Limits|Requests' -A2 | head -12
    Limits:
      cpu:     200m
      memory:  128Mi
    Requests:
      cpu:        50m
      memory:     64Mi
--
QoS Class:                   Burstable
Node-Selectors:              <none>
Tolerations:                 node.kubernetes.io/not-ready:NoExecute op=Exists for 300s
$ kubectl get pod yatri-demo-pod -n s10-objects -o jsonpath='ownerReferences: {.metadata.ownerReferences}{"\n"}'
ownerReferences: 
$ kubectl delete pod yatri-demo-pod -n s10-objects
pod "yatri-demo-pod" deleted from s10-objects namespace
$ kubectl get pod yatri-demo-pod -n s10-objects
Error from server (NotFound): pods "yatri-demo-pod" not found
```

The Pod has requests lower than limits, so its QoS class is `Burstable`. It has no `ownerReferences`, so once deleted it is gone: nothing recreates a bare Pod.

#### ReplicaSet ([core-objects/replicaset.yaml](core-objects/replicaset.yaml))

```bash
$ kubectl get rs yatri-backend-rs -n s10-objects -o wide
NAME               DESIRED   CURRENT   READY   AGE   CONTAINERS   IMAGES                                             SELECTOR
yatri-backend-rs   3         3         3       22s   backend      public.ecr.aws/docker/library/python:3.11-alpine   app=yatri-backend
$ kubectl get pods -n s10-objects -l app=yatri-backend
NAME                     READY   STATUS    RESTARTS   AGE
yatri-backend-rs-5cr5b   1/1     Running   0          22s
yatri-backend-rs-p5wsp   1/1     Running   0          22s
yatri-backend-rs-ts48x   1/1     Running   0          22s
$ kubectl delete pod -n s10-objects $(kubectl get pods -n s10-objects -l app=yatri-backend -o jsonpath='{.items[0].metadata.name}')
pod "yatri-backend-rs-5cr5b" deleted from s10-objects namespace
$ kubectl get pods -n s10-objects -l app=yatri-backend
NAME                     READY   STATUS    RESTARTS   AGE
yatri-backend-rs-fc52m   1/1     Running   0          31s
yatri-backend-rs-p5wsp   1/1     Running   0          53s
yatri-backend-rs-ts48x   1/1     Running   0          53s
$ kubectl describe rs yatri-backend-rs -n s10-objects | sed -n '/^Events:/,$p'
Events:
  Type    Reason            Age   From                   Message
  ----    ------            ----  ----                   -------
  Normal  SuccessfulCreate  53s   replicaset-controller  Created pod: yatri-backend-rs-ts48x
  Normal  SuccessfulCreate  53s   replicaset-controller  Created pod: yatri-backend-rs-5cr5b
  Normal  SuccessfulCreate  53s   replicaset-controller  Created pod: yatri-backend-rs-p5wsp
  Normal  SuccessfulCreate  31s   replicaset-controller  Created pod: yatri-backend-rs-fc52m
$ kubectl scale rs yatri-backend-rs -n s10-objects --replicas=2
replicaset.apps/yatri-backend-rs scaled
$ sleep 3; kubectl get rs yatri-backend-rs -n s10-objects
NAME               DESIRED   CURRENT   READY   AGE
yatri-backend-rs   2         2         2       56s
```

When I deleted Pod `5cr5b`, the ReplicaSet controller created `fc52m` to get back to 3 (see the 4th `SuccessfulCreate` event). Scaling to 2 removed one Pod. The Python server listens on IPv4 only, so inside the container I used `127.0.0.1` (busybox `wget localhost` tried `::1` first and was refused):

```bash
$ kubectl exec -n s10-objects $(kubectl get pods -n s10-objects -l app=yatri-backend -o jsonpath='{.items[0].metadata.name}') -- wget -qO- http://localhost:5000 | head -3
wget: can't connect to remote host: Connection refused
command terminated with exit code 1
```

```bash
$ kubectl exec -n s10-objects $(kubectl get pods -n s10-objects -l app=yatri-backend -o jsonpath='{.items[0].metadata.name}') -- netstat -tln
Active Internet connections (only servers)
Proto Recv-Q Send-Q Local Address           Foreign Address         State       
tcp        0      0 0.0.0.0:5000            0.0.0.0:*               LISTEN      
$ kubectl exec -n s10-objects $(kubectl get pods -n s10-objects -l app=yatri-backend -o jsonpath='{.items[0].metadata.name}') -- wget -qO- http://127.0.0.1:5000 | head -4
<!DOCTYPE HTML>
<html lang="en">
<head>
<meta charset="utf-8">
```

#### Deployment ([core-objects/deployment-v1.yaml](core-objects/deployment-v1.yaml) → [deployment-v2.yaml](core-objects/deployment-v2.yaml))

I deleted the bare ReplicaSet first (its Pods share the label `app=yatri-backend`, which is why two of them still show as `Terminating` below).

```bash
$ kubectl apply -n s10-objects -f core-objects/deployment-v1.yaml
deployment.apps/yatri-backend created
$ kubectl rollout status deployment/yatri-backend -n s10-objects --timeout=180s
Waiting for deployment "yatri-backend" rollout to finish: 0 of 3 updated replicas are available...
Waiting for deployment "yatri-backend" rollout to finish: 1 of 3 updated replicas are available...
Waiting for deployment "yatri-backend" rollout to finish: 2 of 3 updated replicas are available...
deployment "yatri-backend" successfully rolled out
$ kubectl get deploy,rs,pods -n s10-objects -l app=yatri-backend -L version
NAME                            READY   UP-TO-DATE   AVAILABLE   AGE   VERSION
deployment.apps/yatri-backend   3/3     3            3           1s    1.0.0

NAME                                       DESIRED   CURRENT   READY   AGE   VERSION
replicaset.apps/yatri-backend-6d6967cb87   3         3         3       1s    1.0.0

NAME                                 READY   STATUS        RESTARTS   AGE    VERSION
pod/yatri-backend-6d6967cb87-vnw6m   1/1     Running       0          1s     1.0.0
pod/yatri-backend-6d6967cb87-xczbf   1/1     Running       0          1s     1.0.0
pod/yatri-backend-6d6967cb87-z9fcl   1/1     Running       0          1s     1.0.0
pod/yatri-backend-rs-p5wsp           1/1     Terminating   0          115s   
pod/yatri-backend-rs-ts48x           1/1     Terminating   0          115s   
$ kubectl apply -n s10-objects -f core-objects/deployment-v2.yaml
deployment.apps/yatri-backend configured
$ kubectl rollout status deployment/yatri-backend -n s10-objects --timeout=240s
Waiting for deployment "yatri-backend" rollout to finish: 1 out of 3 new replicas have been updated...
Waiting for deployment "yatri-backend" rollout to finish: 1 out of 3 new replicas have been updated...
Waiting for deployment "yatri-backend" rollout to finish: 1 out of 3 new replicas have been updated...
Waiting for deployment "yatri-backend" rollout to finish: 2 out of 3 new replicas have been updated...
Waiting for deployment "yatri-backend" rollout to finish: 2 out of 3 new replicas have been updated...
Waiting for deployment "yatri-backend" rollout to finish: 2 out of 3 new replicas have been updated...
Waiting for deployment "yatri-backend" rollout to finish: 1 old replicas are pending termination...
Waiting for deployment "yatri-backend" rollout to finish: 1 old replicas are pending termination...
deployment "yatri-backend" successfully rolled out
$ kubectl get rs -n s10-objects -l app=yatri-backend -L version
NAME                       DESIRED   CURRENT   READY   AGE   VERSION
yatri-backend-675b74fcd5   3         3         3       1s    2.0.0
yatri-backend-6d6967cb87   0         0         0       2s    1.0.0
$ kubectl describe deploy yatri-backend -n s10-objects | grep -E '^(StrategyType|RollingUpdateStrategy)'
StrategyType:           RollingUpdate
RollingUpdateStrategy:  0 max unavailable, 1 max surge
$ kubectl rollout history deployment/yatri-backend -n s10-objects
deployment.apps/yatri-backend 
REVISION  CHANGE-CAUSE
1         <none>
2         <none>
```

v1 and v2 differ in the version label and the rolling-update settings (v2 uses `maxUnavailable: 0`). Each applied template got its own ReplicaSet (`6d6967cb87` for 1.0.0, `675b74fcd5` for 2.0.0) and a revision in the history.

#### DaemonSet ([core-objects/daemonset.yaml](core-objects/daemonset.yaml))

```bash
$ kubectl get ds node-logging-agent -n s10-objects -o wide
NAME                 DESIRED   CURRENT   READY   UP-TO-DATE   AVAILABLE   NODE SELECTOR   AGE   CONTAINERS      IMAGES                                       SELECTOR
node-logging-agent   1         1         1       1            1           <none>          56s   fluent-logger   public.ecr.aws/docker/library/busybox:1.36   app=node-logging-agent
$ kubectl get nodes
NAME       STATUS   ROLES           AGE   VERSION
minikube   Ready    control-plane   29m   v1.37.0
$ kubectl get pods -n s10-objects -l app=node-logging-agent -o wide
NAME                       READY   STATUS    RESTARTS   AGE   IP             NODE       NOMINATED NODE   READINESS GATES
node-logging-agent-zr6st   1/1     Running   0          56s   10.244.0.156   minikube   <none>           <none>
$ kubectl logs -n s10-objects -l app=node-logging-agent --tail=2
[Wed Oct  7 18:05:47 UTC 2026] Collecting host system metrics on node-logging-agent-zr6st
[Wed Oct  7 18:05:57 UTC 2026] Collecting host system metrics on node-logging-agent-zr6st
```

A DaemonSet has no `replicas` field. DESIRED is the number of eligible nodes, which is 1 here, so there is exactly one agent Pod, and it logs the node it is running on. On a 3-node cluster the same YAML would give 3 Pods.

#### StatefulSet ([core-objects/statefulset.yaml](core-objects/statefulset.yaml))

The course's [statefulset-mysql-course.yaml](core-objects/statefulset-mysql-course.yaml) uses `mysql:5.7`, which is published for linux/amd64 only, and asks for 3 x 5Gi volumes plus three MySQL servers. That is too heavy for a shared laptop node, so I did not run it. 

```bash
$ docker buildx imagetools inspect public.ecr.aws/docker/library/mysql:5.7 | grep Platform
  Platform:    linux/amd64
  Platform:    unknown/unknown
```

Instead I wrote a small StatefulSet (nginx, 2 replicas, a 16Mi PVC each, a headless Service) that shows the same three properties: stable names, ordered creation, and one volume per Pod that survives Pod restarts.

```bash
$ kubectl get sts,svc,pvc -n s10-objects
NAME                       READY   AGE
statefulset.apps/web-sts   2/2     81s

NAME              TYPE        CLUSTER-IP   EXTERNAL-IP   PORT(S)   AGE
service/web-sts   ClusterIP   None         <none>        80/TCP    81s

NAME                                  STATUS   VOLUME                                     CAPACITY   ACCESS MODES   STORAGECLASS   VOLUMEATTRIBUTESCLASS   AGE
persistentvolumeclaim/www-web-sts-0   Bound    pvc-da9c2558-e282-4898-81cc-00a86f2c4f6d   16Mi       RWO            standard       <unset>                 81s
persistentvolumeclaim/www-web-sts-1   Bound    pvc-3314529a-9001-4fe8-a500-a6232f8537b2   16Mi       RWO            standard       <unset>                 81s
$ kubectl get pods -n s10-objects -l app=web-sts -o wide
NAME        READY   STATUS    RESTARTS   AGE   IP             NODE       NOMINATED NODE   READINESS GATES
web-sts-0   1/1     Running   0          81s   10.244.0.157   minikube   <none>           <none>
web-sts-1   1/1     Running   0          81s   10.244.0.158   minikube   <none>           <none>
$ for p in web-sts-0 web-sts-1; do kubectl exec -n s10-objects $p -- sh -c "echo data written by $p > /usr/share/nginx/html/index.html"; done
$ kubectl exec -n s10-client curl-client -- curl -s http://web-sts-0.web-sts.s10-objects.svc.cluster.local
data written by web-sts-0
$ kubectl exec -n s10-client curl-client -- curl -s http://web-sts-1.web-sts.s10-objects.svc.cluster.local
data written by web-sts-1
$ kubectl delete pod web-sts-0 -n s10-objects
pod "web-sts-0" deleted from s10-objects namespace
$ kubectl wait -n s10-objects --for=condition=Ready pod/web-sts-0 --timeout=120s
pod/web-sts-0 condition met
$ kubectl get pods -n s10-objects -l app=web-sts -o wide
NAME        READY   STATUS    RESTARTS   AGE   IP             NODE       NOMINATED NODE   READINESS GATES
web-sts-0   1/1     Running   0          1s    10.244.0.173   minikube   <none>           <none>
web-sts-1   1/1     Running   0          83s   10.244.0.158   minikube   <none>           <none>
$ kubectl exec -n s10-client curl-client -- curl -s http://web-sts-0.web-sts.s10-objects.svc.cluster.local
command terminated with exit code 7
```

The Pod `web-sts-0` was recreated with **the same name** but a new IP (10.244.0.157 → 10.244.0.173). The first request right after the restart failed (exit 7, could not connect), most likely because the DNS record, which CoreDNS builds from the EndpointSlice, still pointed at the old IP for a moment. A few seconds later the name resolved to the new IP, and the data written before the restart was still on the volume:

```bash
$ kubectl exec -n s10-client curl-client -- nslookup web-sts-0.web-sts.s10-objects.svc.cluster.local
Server:		10.96.0.10
Address:	10.96.0.10:53


Name:	web-sts-0.web-sts.s10-objects.svc.cluster.local
Address: 10.244.0.173
$ kubectl exec -n s10-client curl-client -- curl -s http://web-sts-0.web-sts.s10-objects.svc.cluster.local
data written by web-sts-0
$ kubectl exec -n s10-objects web-sts-0 -- cat /usr/share/nginx/html/index.html
data written by web-sts-0
```

Scaling up creates the next ordinal with its own new PVC:

```bash
$ kubectl scale sts web-sts -n s10-objects --replicas=3
statefulset.apps/web-sts scaled
$ sleep 12; kubectl get pods -n s10-objects -l app=web-sts
NAME        READY   STATUS    RESTARTS   AGE
web-sts-0   1/1     Running   0          13s
web-sts-1   1/1     Running   0          95s
web-sts-2   1/1     Running   0          12s
$ kubectl get pvc -n s10-objects
NAME            STATUS   VOLUME                                     CAPACITY   ACCESS MODES   STORAGECLASS   VOLUMEATTRIBUTESCLASS   AGE
www-web-sts-0   Bound    pvc-da9c2558-e282-4898-81cc-00a86f2c4f6d   16Mi       RWO            standard       <unset>                 95s
www-web-sts-1   Bound    pvc-3314529a-9001-4fe8-a500-a6232f8537b2   16Mi       RWO            standard       <unset>                 95s
www-web-sts-2   Bound    pvc-edccaeea-fbe7-4441-98fc-0e180090a9c7   16Mi       RWO            standard       <unset>                 12s
$ kubectl describe sts web-sts -n s10-objects | sed -n '/^Events:/,$p'
Events:
  Type    Reason            Age                From                    Message
  ----    ------            ----               ----                    -------
  Normal  SuccessfulCreate  95s                statefulset-controller  Create Claim www-web-sts-0 Pod web-sts-0 in StatefulSet web-sts success
  Normal  SuccessfulCreate  95s                statefulset-controller  Create Claim www-web-sts-1 Pod web-sts-1 in StatefulSet web-sts success
  Normal  SuccessfulCreate  95s                statefulset-controller  Create Pod web-sts-1 in StatefulSet web-sts successful
  Normal  SuccessfulCreate  13s (x2 over 95s)  statefulset-controller  Create Pod web-sts-0 in StatefulSet web-sts successful
  Normal  SuccessfulCreate  12s                statefulset-controller  Create Claim www-web-sts-2 Pod web-sts-2 in StatefulSet web-sts success
  Normal  SuccessfulCreate  12s                statefulset-controller  Create Pod web-sts-2 in StatefulSet web-sts successful
```

### Troubleshooting drills (course `troubleshooting/` folder)

**Rollout to a broken image.** I deployed v2 of `yatri-backend` and then applied [troubleshooting/broken-image.yaml](troubleshooting/broken-image.yaml), which points at `yatri-backend:non-existent-tag-v999`:

```bash
$ kubectl create namespace s10-troubleshoot
namespace/s10-troubleshoot created
$ kubectl apply -n s10-troubleshoot -f core-objects/deployment-v2.yaml
deployment.apps/yatri-backend created
$ kubectl rollout status deployment/yatri-backend -n s10-troubleshoot --timeout=120s
Waiting for deployment "yatri-backend" rollout to finish: 0 of 3 updated replicas are available...
Waiting for deployment "yatri-backend" rollout to finish: 1 of 3 updated replicas are available...
Waiting for deployment "yatri-backend" rollout to finish: 2 of 3 updated replicas are available...
deployment "yatri-backend" successfully rolled out
$ kubectl apply -n s10-troubleshoot -f troubleshooting/broken-image.yaml
deployment.apps/yatri-backend configured
$ kubectl rollout status deployment/yatri-backend -n s10-troubleshoot --timeout=30s
Waiting for deployment "yatri-backend" rollout to finish: 1 out of 3 new replicas have been updated...
error: timed out waiting for the condition
$ kubectl get rs,pods -n s10-troubleshoot -L version
NAME                                       DESIRED   CURRENT   READY   AGE   VERSION
replicaset.apps/yatri-backend-675b74fcd5   3         3         3       31s   2.0.0
replicaset.apps/yatri-backend-77dbb657cd   1         1         0       30s   broken-v3

NAME                                 READY   STATUS         RESTARTS   AGE   VERSION
pod/yatri-backend-675b74fcd5-7qr2q   1/1     Running        0          31s   2.0.0
pod/yatri-backend-675b74fcd5-llh2x   1/1     Running        0          31s   2.0.0
pod/yatri-backend-675b74fcd5-qkpgs   1/1     Running        0          31s   2.0.0
pod/yatri-backend-77dbb657cd-j2w4k   0/1     ErrImagePull   0          30s   broken-v3
$ kubectl get events -n s10-troubleshoot --field-selector reason=Failed -o jsonpath='{range .items[*]}{.message}{"\n"}{end}' | sort -u
Error: ErrImagePull
Error: ImagePullBackOff
Failed to pull image "yatri-backend:non-existent-tag-v999": failed to pull and unpack image "docker.io/library/yatri-backend:non-existent-tag-v999": failed to resolve reference "docker.io/library/yatri-backend:non-existent-tag-v999": pull access denied, repository does not exist or may require authorization: server message: insufficient_scope: authorization failed
```

Because the strategy has `maxUnavailable: 0`, Kubernetes created one surge Pod with the broken image and did **not** remove any healthy Pod while it could not become ready. All three v2 Pods kept serving. The event gives the real cause: the repository `docker.io/library/yatri-backend` does not exist (`pull access denied`). The fix is a rollback:

```bash
$ kubectl rollout undo deployment/yatri-backend -n s10-troubleshoot
Warning: resource deployments/yatri-backend was previously managed with 'kubectl apply'. Rolling back will not update the kubectl.kubernetes.io/last-applied-configuration annotation, which may cause unexpected behavior on future 'kubectl apply' operations. Consider using 'kubectl apply' with your previous configuration file instead.
deployment.apps/yatri-backend rolled back
$ kubectl rollout status deployment/yatri-backend -n s10-troubleshoot --timeout=120s
deployment "yatri-backend" successfully rolled out
$ sleep 5; kubectl get rs,pods -n s10-troubleshoot -L version
NAME                                       DESIRED   CURRENT   READY   AGE   VERSION
replicaset.apps/yatri-backend-675b74fcd5   3         3         3       36s   2.0.0
replicaset.apps/yatri-backend-77dbb657cd   0         0         0       35s   broken-v3

NAME                                 READY   STATUS    RESTARTS   AGE   VERSION
pod/yatri-backend-675b74fcd5-7qr2q   1/1     Running   0          36s   2.0.0
pod/yatri-backend-675b74fcd5-llh2x   1/1     Running   0          36s   2.0.0
pod/yatri-backend-675b74fcd5-qkpgs   1/1     Running   0          36s   2.0.0
```

**Selector does not match the template labels.** The API server rejects [troubleshooting/selector-mismatch.yaml](troubleshooting/selector-mismatch.yaml) before anything is created, because a Deployment whose selector does not match its own Pod template could never manage its Pods:

```bash
$ kubectl apply -n s10-troubleshoot -f troubleshooting/selector-mismatch.yaml
The Deployment "selector-error-demo" is invalid: spec.template.metadata.labels: Invalid value: {"app":"wrong-app-name"}: `selector` does not match template `labels`
```

## Cleanup

I deleted each namespace when I finished with it (`s10-rolling`, `s10-bluegreen`, `s10-canary`, `s10-recreate`, `s10-lifecycle`, `s10-troubleshoot`). The last two:

```bash
$ kubectl delete namespace s10-objects s10-client
namespace "s10-objects" deleted
namespace "s10-client" deleted
$ kubectl get ns | grep -E '^s10-' || echo 'no s10- namespaces left'
no s10- namespaces left
```

Deleting the namespaces also removed the StatefulSet PVCs, and their PVs were deleted too because the `standard` StorageClass uses reclaim policy `Delete`:

```bash
$ kubectl get storageclass standard
NAME       PROVISIONER                RECLAIMPOLICY   VOLUMEBINDINGMODE   ALLOWVOLUMEEXPANSION   AGE
standard   k8s.io/minikube-hostpath   Delete          Immediate           false                  50m
```
 I stopped all background watches and request loops.

## What I learned

- A Deployment never updates Pods in place. It creates a new ReplicaSet and moves replicas between the old and the new one. maxSurge/maxUnavailable decide how many move at a time, and the old ReplicaSet kept at 0 is what makes `rollout undo` instant.
- I can measure downtime instead of guessing: Rolling Update 0 failed requests, Blue-Green 0 during the switch, Recreate about 1.5 s of failures even with a cached image.
- Canary with plain Kubernetes is only a replica ratio plus a shared label, so the split is coarse and random per connection.
- Running is not Ready. Readiness removes a Pod from traffic, liveness restarts the container, and startup protects slow starters from liveness.
- PID 1 must handle SIGTERM. Otherwise every restart or delete waits the whole grace period and ends with SIGKILL (exit 137).
- Events in `kubectl describe` and the container `state`/`lastState` give the real reason (Unschedulable, repository does not exist, exit codes). The STATUS column is only a summary.
- On a shared cluster, fixed NodePorts and large resource requests are global side effects, and I had to change them in the course files.
