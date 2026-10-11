# Session 13: Storage, HPA & Probes

**Name:** Vansh Srivastava
**Enrollment No.:** 24bcs10567
**Session:** 13

This session covers keeping data when Pods come and go (volumes, PV/PVC, StorageClasses), scaling Pods with CPU load (HorizontalPodAutoscaler), and telling Kubernetes whether an app is started, ready and alive (probes). I ran every volume type on the shared minikube cluster, ran the course HPA demo through a full scale-out and scale-in with a load generator, and completed the course mini project (PVC + HPA + startup/readiness/liveness probes), including its probe-breaking challenges.

Course material comes from https://github.com/Nency-Ravaliya/devops-heros (folder `session-13-storage-hpa-probes`). Copied files say so in their header, together with my changes.

## Folder structure

```text
session-13-storage-hpa-probes/
├── README.md
├── .gitignore
├── 01-kubernetes-volumes/
│   ├── README.md                    # Task 1: emptyDir, hostPath, PV, PVC, StorageClass, dynamic provisioning
│   ├── namespace.yaml               # s13-volumes
│   ├── 01-emptydir-shared.yaml      # emptyDir shared by two containers
│   ├── 02-hostpath-pod.yaml         # hostPath (course file)
│   ├── 03-static-pv.yaml / 03-static-pvc.yaml / 03-static-pod.yaml   # static PV + PVC, Retain
│   ├── 04-dynamic-pvc.yaml          # dynamic PVC on the standard StorageClass + Pod
│   ├── 05-storageclass-wffc.yaml / 05-wffc-pod.yaml / 05-provisioner-rbac-fix.yaml
│   └── course-original/             # course pv.yaml / pvc.yaml (renamed) used to show a binding gotcha
├── 02-hpa/
│   ├── namespace.yaml               # s13-hpa
│   ├── deployment.yaml              # course 04-hpa/deployment.yaml (nginx, cpu request 100m)
│   ├── service.yaml                 # course 04-hpa/service.yaml
│   ├── hpa.yaml                     # course 04-hpa/hpa.yaml + behavior.scaleDown 60 s
│   ├── load-generator.yaml          # busybox wget loop as a scalable Deployment
│   └── watch-hpa.sh                 # timestamped get hpa / get pods / top pods every N seconds
├── 03-mini-project/
│   ├── COURSE-INSTRUCTIONS.md       # the course mini-project README (instructions)
│   ├── namespace.yaml, pvc.yaml, deployment.yaml, service.yaml, hpa.yaml   # course files, namespace s13-production-webapp
│   └── load-generator.yaml          # the course load generator as a manifest
└── screenshots/
    └── 01-mini-project-web-service.png
```

## Environment

- macOS on Apple Silicon (arm64), Docker via Colima, minikube v1.39.0 with Kubernetes v1.37.0 (containerd), one shared node with 6 CPUs.
- Addons used: `metrics-server` (runs with `--metric-resolution=60s`, which matters for HPA timing) and `storage-provisioner` / `default-storageclass` (the `standard` class).
- My namespaces: `s13-volumes`, `s13-hpa`, `s13-production-webapp`. Cluster-scoped objects are prefixed `s13-`.
- Images come from the AWS ECR Public mirror of the official images (`public.ecr.aws/docker/library/nginx:1.27`, `.../busybox:1.36`), because Docker Hub answered `429 Too Many Requests` from this network (the full error is in the Session 12 README).
- The node IP is not reachable from my Mac, so I used `kubectl port-forward` on port 18230.

## Task 1: Kubernetes volumes

The full documentation with every example and its output is in [01-kubernetes-volumes/README.md](01-kubernetes-volumes/README.md). In short:

| Topic | What I did | Result |
| :--- | :--- | :--- |
| emptyDir | `writer` (busybox) and `web` (nginx) containers share one emptyDir | nginx served the file the other container wrote. After deleting the Pod the old content was gone |
| hostPath | wrote `/data/message.txt`, deleted and recreated the Pod | file still there, also visible on the node with `minikube ssh` |
| PV + PVC (static) | hand-made PV `s13-student-pv` (Retain) + PVC + Pod | data survived Pod deletion. After deleting the PVC the PV was `Released` and the data was still on the node |
| Binding gotcha | course `pv.yaml` + `pvc.yaml` as they are | the PVC got the default class `standard` and a new dynamic volume, not the hand-made PV. Fix: `storageClassName: ""` on both |
| StorageClass / dynamic | PVC on `standard` | PV `pvc-469c...` created automatically, deleted together with the PVC (`Delete` policy) |
| Own StorageClass | `s13-wffc` with `WaitForFirstConsumer` | claim waited for a Pod as expected, then failed: the minikube provisioner may not `get nodes`. Granting that one verb fixed it |

## Task 2: HPA hands-on

### Files

- [02-hpa/deployment.yaml](02-hpa/deployment.yaml), [02-hpa/service.yaml](02-hpa/service.yaml), [02-hpa/hpa.yaml](02-hpa/hpa.yaml) are the course `04-hpa` files (nginx, CPU request `100m`, limit `200m`; HPA min 1, max 5, target 50% average CPU). I used `04-hpa` rather than the `hpa/` folder because `hpa/hpa-backend.yaml` targets the Session 12 `yatri-backend` Deployment, which that folder does not contain.
- My one change to the HPA is a `behavior` block: `scaleDown.stabilizationWindowSeconds: 60`. By default the HPA waits 300 seconds of consistently lower recommendations before it removes Pods (so it does not flap when load goes up and down). I shortened it so scale-in can be seen in a lab run. The mini project in Task 3 keeps the default, so both are shown.
- [02-hpa/load-generator.yaml](02-hpa/load-generator.yaml) is the course `kubectl run load-generator ... wget` loop as a Deployment, so I can increase the load by adding replicas. Each replica is limited to 250m CPU.
- [02-hpa/watch-hpa.sh](02-hpa/watch-hpa.sh) prints a timestamped snapshot of `kubectl get hpa`, `kubectl get pods` and `kubectl top pods` every 20 seconds. I ran it in the background during the test.

How the HPA calculates: utilization = pod CPU usage / pod CPU **request**. desiredReplicas = ceil(currentReplicas x currentUtilization / 50%). Without a CPU request there is nothing to divide by, and the HPA shows `<unknown>`.

### Deploy the app

```bash
$ kubectl apply -f namespace.yaml -f deployment.yaml -f service.yaml
namespace/s13-hpa created
deployment.apps/hpa-demo created
service/hpa-demo-service created
$ kubectl -n s13-hpa rollout status deploy/hpa-demo --timeout=120s
Waiting for deployment "hpa-demo" rollout to finish: 0 of 1 updated replicas are available...
deployment "hpa-demo" successfully rolled out
$ kubectl -n s13-hpa get deploy,pods,svc -o wide
NAME                       READY   UP-TO-DATE   AVAILABLE   AGE   CONTAINERS   IMAGES                                     SELECTOR
deployment.apps/hpa-demo   1/1     1            1           4s    nginx        public.ecr.aws/docker/library/nginx:1.27   app=hpa-demo

NAME                            READY   STATUS    RESTARTS   AGE   IP            NODE       NOMINATED NODE   READINESS GATES
pod/hpa-demo-7f57cbc6f7-gc45z   1/1     Running   0          4s    10.244.0.96   minikube   <none>           <none>

NAME                       TYPE        CLUSTER-IP      EXTERNAL-IP   PORT(S)   AGE   SELECTOR
service/hpa-demo-service   ClusterIP   10.98.207.130   <none>        80/TCP    4s    app=hpa-demo
$ kubectl get apiservice v1beta1.metrics.k8s.io
NAME                     SERVICE                      AVAILABLE   AGE
v1beta1.metrics.k8s.io   kube-system/metrics-server   True        21m
$ kubectl -n kube-system get pods -l k8s-app=metrics-server
NAME                              READY   STATUS    RESTARTS   AGE
metrics-server-768f9f6999-d4rzf   1/1     Running   0          21m
$ kubectl -n kube-system get deploy metrics-server -o jsonpath='{.spec.template.spec.containers[0].args}'; echo
["--cert-dir=/tmp","--secure-port=4443","--kubelet-preferred-address-types=InternalIP,ExternalIP,Hostname","--kubelet-use-node-status-port","--metric-resolution=60s","--kubelet-insecure-tls"]
```

### Configure and verify the HPA

```bash
$ kubectl apply -f hpa.yaml
horizontalpodautoscaler.autoscaling/hpa-demo created
$ date +%H:%M:%S; kubectl -n s13-hpa get hpa
23:29:38
NAME       REFERENCE             TARGETS              MINPODS   MAXPODS   REPLICAS   AGE
hpa-demo   Deployment/hpa-demo   cpu: <unknown>/50%   1         5         1          1s
$ date +%H:%M:%S; kubectl -n s13-hpa get hpa
23:30:08
NAME       REFERENCE             TARGETS              MINPODS   MAXPODS   REPLICAS   AGE
hpa-demo   Deployment/hpa-demo   cpu: <unknown>/50%   1         5         1          31s
$ kubectl -n s13-hpa top pods
error: metrics not available yet
$ kubectl -n s13-hpa describe hpa hpa-demo
Name:                                                  hpa-demo
Namespace:                                             s13-hpa
Labels:                                                <none>
Annotations:                                           <none>
CreationTimestamp:                                     Wed, 07 Oct 2026 23:29:38 +0530
Reference:                                             Deployment/hpa-demo
Metrics:                                               ( current / target )
  resource cpu on pods  (as a percentage of request):  <unknown> / 50%
Min replicas:                                          1
Max replicas:                                          5
Behavior:
  Scale Up:
    Stabilization Window: 0 seconds
    Select Policy: Max
    Policies:
      - Type: Pods     Value: 4    Period: 15 seconds
      - Type: Percent  Value: 100  Period: 15 seconds
  Scale Down:
    Stabilization Window: 60 seconds
    Select Policy: Max
    Policies:
      - Type: Percent  Value: 100  Period: 15 seconds
Deployment pods:       1 current / 0 desired
Conditions:
  Type           Status  Reason                   Message
  ----           ------  ------                   -------
  AbleToScale    True    SucceededGetScale        the HPA controller was able to get the target's current scale
  ScalingActive  False   FailedGetResourceMetric  the HPA was unable to compute the replica count: failed to get cpu utilization: unable to get metrics for resource cpu: no metrics returned from resource metrics API
Events:
  Type     Reason                        Age               From                       Message
  ----     ------                        ----              ----                       -------
  Warning  FailedGetResourceMetric       1s (x3 over 31s)  horizontal-pod-autoscaler  failed to get cpu utilization: unable to get metrics for resource cpu: no metrics returned from resource metrics API
  Warning  FailedComputeMetricsReplicas  1s (x3 over 31s)  horizontal-pod-autoscaler  invalid metrics (1 invalid out of 1), first error is: failed to get cpu resource metric value: failed to get cpu utilization: unable to get metrics for resource cpu: no metrics returned from resource metrics API
```

`<unknown>` right after creation is normal: metrics-server collects only every 60 seconds, and the HPA also ignores CPU samples taken before the Pod became Ready. The `Behavior` section shows the defaults for scale-up (add up to 4 Pods or 100% every 15 s, no waiting) and my 60 s scale-down window. About a minute later:

```bash
$ date +%H:%M:%S; kubectl -n s13-hpa get hpa
23:30:54
NAME       REFERENCE             TARGETS       MINPODS   MAXPODS   REPLICAS   AGE
hpa-demo   Deployment/hpa-demo   cpu: 1%/50%   1         5         1          76s
$ kubectl -n s13-hpa describe hpa hpa-demo | sed -n "/^Metrics/,/^Max/p;/^Conditions/,/^Events/p"
Metrics:                                               ( current / target )
  resource cpu on pods  (as a percentage of request):  1% (1m) / 50%
Min replicas:                                          1
Max replicas:                                          5
Conditions:
  Type            Status  Reason              Message
  ----            ------  ------              -------
  AbleToScale     True    ReadyForNewScale    recommended size matches current size
  ScalingActive   True    ValidMetricFound    the HPA was able to successfully calculate a replica count from cpu resource utilization (percentage of request)
  ScalingLimited  False   DesiredWithinRange  the desired count is within the acceptable range
Events:
```

### Deploy the load generator and increase the load

```bash
$ date +%H:%M:%S
23:31:02
$ kubectl apply -f load-generator.yaml
deployment.apps/load-generator created
$ kubectl -n s13-hpa rollout status deploy/load-generator --timeout=90s
Waiting for deployment "load-generator" rollout to finish: 0 of 1 updated replicas are available...
deployment "load-generator" successfully rolled out
$ kubectl -n s13-hpa logs deploy/load-generator
sending requests to http://10.98.207.130:80/
```

One generator brought nginx to 48% of its request, just under the 50% target, so I increased the load to three generators:

```bash
$ date +%H:%M:%S; kubectl -n s13-hpa get hpa; kubectl -n s13-hpa top pods
23:32:44
NAME       REFERENCE             TARGETS        MINPODS   MAXPODS   REPLICAS   AGE
hpa-demo   Deployment/hpa-demo   cpu: 48%/50%   1         5         1          3m6s
NAME                              CPU(cores)   MEMORY(bytes)   
hpa-demo-7f57cbc6f7-gc45z         58m          8Mi             
load-generator-848687b85f-ndbp2   253m         8Mi             
$ kubectl -n s13-hpa scale deploy/load-generator --replicas=3
deployment.apps/load-generator scaled
$ kubectl -n s13-hpa rollout status deploy/load-generator --timeout=60s
Waiting for deployment "load-generator" rollout to finish: 1 of 3 updated replicas are available...
Waiting for deployment "load-generator" rollout to finish: 2 of 3 updated replicas are available...
deployment "load-generator" successfully rolled out
$ kubectl top pods -n kube-system -l k8s-app=kube-dns
NAME                       CPU(cores)   MEMORY(bytes)   
coredns-559f6c778d-mb9q4   2m           15Mi           
```

(The last command checks that CoreDNS stays idle. See the note on my first attempt below.)

### Observe CPU utilization and Pod scaling

Excerpts from `./watch-hpa.sh s13-hpa 20` running in the background (each block: HPA line, Pods, `kubectl top pods`):

```text
===== 23:31:22 =====
hpa-demo   Deployment/hpa-demo   cpu: 1%/50%   1     5     1     104s
hpa-demo-7f57cbc6f7-gc45z   1/1   Running   0     108s
hpa-demo-7f57cbc6f7-gc45z   1m    7Mi   
===== 23:31:42 =====
hpa-demo   Deployment/hpa-demo   cpu: 1%/50%   1     5     1     2m4s
hpa-demo-7f57cbc6f7-gc45z   1/1   Running   0     2m8s
hpa-demo-7f57cbc6f7-gc45z         48m    8Mi   
load-generator-848687b85f-ndbp2   251m   5Mi   
===== 23:32:02 =====
hpa-demo   Deployment/hpa-demo   cpu: 48%/50%   1     5     1     2m24s
hpa-demo-7f57cbc6f7-gc45z   1/1   Running   0     2m28s
hpa-demo-7f57cbc6f7-gc45z         48m    8Mi   
load-generator-848687b85f-ndbp2   251m   5Mi   
...
hpa-demo   Deployment/hpa-demo   cpu: 77%/50%   1     5     3     5m25s
hpa-demo-7f57cbc6f7-24sdt   1/1   Running   0     11s
hpa-demo-7f57cbc6f7-7znk2   1/1   Running   0     2m11s
hpa-demo-7f57cbc6f7-gc45z   1/1   Running   0     5m29s
hpa-demo-7f57cbc6f7-hrwjn   1/1   Running   0     11s
hpa-demo-7f57cbc6f7-mwprs   1/1   Running   0     71s
hpa-demo-7f57cbc6f7-7znk2         77m    6Mi   
hpa-demo-7f57cbc6f7-gc45z         75m    8Mi   
hpa-demo-7f57cbc6f7-mwprs         80m    6Mi   
load-generator-848687b85f-fshxb   252m   6Mi   
load-generator-848687b85f-ndbp2   252m   6Mi   
load-generator-848687b85f-qgdgr   253m   5Mi   
===== 23:35:23 =====
hpa-demo   Deployment/hpa-demo   cpu: 77%/50%   1     5     5     5m46s
hpa-demo-7f57cbc6f7-24sdt   1/1   Running   0     32s
hpa-demo-7f57cbc6f7-7znk2   1/1   Running   0     2m32s
hpa-demo-7f57cbc6f7-gc45z   1/1   Running   0     5m50s
hpa-demo-7f57cbc6f7-hrwjn   1/1   Running   0     32s
hpa-demo-7f57cbc6f7-mwprs   1/1   Running   0     92s
...
```

At the maximum of 5 replicas:

```bash
$ date +%H:%M:%S; kubectl -n s13-hpa get hpa
23:35:40
NAME       REFERENCE             TARGETS        MINPODS   MAXPODS   REPLICAS   AGE
hpa-demo   Deployment/hpa-demo   cpu: 77%/50%   1         5         5          6m2s
$ kubectl -n s13-hpa get deploy hpa-demo; kubectl -n s13-hpa get pods -o wide
NAME       READY   UP-TO-DATE   AVAILABLE   AGE
hpa-demo   5/5     5            5           6m6s
NAME                              READY   STATUS    RESTARTS   AGE     IP             NODE       NOMINATED NODE   READINESS GATES
hpa-demo-7f57cbc6f7-24sdt         1/1     Running   0          48s     10.244.0.150   minikube   <none>           <none>
hpa-demo-7f57cbc6f7-7znk2         1/1     Running   0          2m48s   10.244.0.134   minikube   <none>           <none>
hpa-demo-7f57cbc6f7-gc45z         1/1     Running   0          6m6s    10.244.0.96    minikube   <none>           <none>
hpa-demo-7f57cbc6f7-hrwjn         1/1     Running   0          48s     10.244.0.151   minikube   <none>           <none>
hpa-demo-7f57cbc6f7-mwprs         1/1     Running   0          108s    10.244.0.143   minikube   <none>           <none>
load-generator-848687b85f-fshxb   1/1     Running   0          2m56s   10.244.0.131   minikube   <none>           <none>
load-generator-848687b85f-ndbp2   1/1     Running   0          4m38s   10.244.0.113   minikube   <none>           <none>
load-generator-848687b85f-qgdgr   1/1     Running   0          2m56s   10.244.0.132   minikube   <none>           <none>
$ kubectl -n s13-hpa top pods
NAME                              CPU(cores)   MEMORY(bytes)   
hpa-demo-7f57cbc6f7-24sdt         48m          6Mi             
hpa-demo-7f57cbc6f7-7znk2         51m          6Mi             
hpa-demo-7f57cbc6f7-gc45z         53m          8Mi             
hpa-demo-7f57cbc6f7-hrwjn         45m          5Mi             
hpa-demo-7f57cbc6f7-mwprs         46m          6Mi             
load-generator-848687b85f-fshxb   252m         5Mi             
load-generator-848687b85f-ndbp2   252m         6Mi             
load-generator-848687b85f-qgdgr   252m         5Mi             
$ kubectl -n s13-hpa describe hpa hpa-demo | sed -n "/^Metrics/,/^Max/p;/^Deployment pods/,\$p"
Metrics:                                               ( current / target )
  resource cpu on pods  (as a percentage of request):  77% (77m) / 50%
Min replicas:                                          1
Max replicas:                                          5
Deployment pods:       5 current / 5 desired
Conditions:
  Type            Status  Reason              Message
  ----            ------  ------              -------
  AbleToScale     True    ReadyForNewScale    recommended size matches current size
  ScalingActive   True    ValidMetricFound    the HPA was able to successfully calculate a replica count from cpu resource utilization (percentage of request)
  ScalingLimited  False   DesiredWithinRange  the desired count is within the acceptable range
  ScaledToZero    False   NotScaledToZero     the HPA controller did not scale the workload to zero
Events:
  Type     Reason                        Age                  From                       Message
  ----     ------                        ----                 ----                       -------
  Warning  FailedGetResourceMetric       5m2s (x5 over 6m2s)  horizontal-pod-autoscaler  failed to get cpu utilization: unable to get metrics for resource cpu: no metrics returned from resource metrics API
  Warning  FailedComputeMetricsReplicas  5m2s (x5 over 6m2s)  horizontal-pod-autoscaler  invalid metrics (1 invalid out of 1), first error is: failed to get cpu resource metric value: failed to get cpu utilization: unable to get metrics for resource cpu: no metrics returned from resource metrics API
  Normal   SuccessfulRescale             2m48s                horizontal-pod-autoscaler  New size: 2; reason: cpu resource utilization (percentage of request) above target
  Normal   SuccessfulRescale             108s                 horizontal-pod-autoscaler  New size: 3; reason: cpu resource utilization (percentage of request) above target
  Normal   SuccessfulRescale             48s                  horizontal-pod-autoscaler  New size: 5; reason: cpu resource utilization (percentage of request) above target
```

With the load spread over 5 Pods, each one uses about 45-53m, close to the 50m target (50% of 100m). The HPA line still showed 77% because it lags one metrics-server cycle behind `kubectl top`.

### Stop the load and observe scale-in

```bash
$ date +%H:%M:%S
23:35:47
$ kubectl delete -f load-generator.yaml
deployment.apps "load-generator" deleted from s13-hpa namespace
```

From the watcher:

```text
===== 23:38:45 =====
hpa-demo   Deployment/hpa-demo   cpu: 0%/50%   1     5     4     9m7s
hpa-demo-7f57cbc6f7-gc45z   1/1   Running   0     9m11s
hpa-demo-7f57cbc6f7-gc45z   0m    8Mi   
===== 23:39:05 =====
hpa-demo   Deployment/hpa-demo   cpu: 0%/50%   1     5     1     9m27s
hpa-demo-7f57cbc6f7-gc45z   1/1   Running   0     9m31s
hpa-demo-7f57cbc6f7-gc45z   0m    8Mi
```

```bash
$ date +%H:%M:%S; kubectl -n s13-hpa get hpa
23:39:11
NAME       REFERENCE             TARGETS       MINPODS   MAXPODS   REPLICAS   AGE
hpa-demo   Deployment/hpa-demo   cpu: 0%/50%   1         5         1          9m34s
$ kubectl -n s13-hpa get pods
NAME                        READY   STATUS    RESTARTS   AGE
hpa-demo-7f57cbc6f7-gc45z   1/1     Running   0          9m38s
$ kubectl -n s13-hpa describe hpa hpa-demo | sed -n "/^Events/,\$p" | grep -E "Events|Type|----|SuccessfulRescale"
Events:
  Type     Reason                        Age                    From                       Message
  ----     ------                        ----                   ----                       -------
  Normal   SuccessfulRescale             6m20s                  horizontal-pod-autoscaler  New size: 2; reason: cpu resource utilization (percentage of request) above target
  Normal   SuccessfulRescale             5m20s                  horizontal-pod-autoscaler  New size: 3; reason: cpu resource utilization (percentage of request) above target
  Normal   SuccessfulRescale             4m20s                  horizontal-pod-autoscaler  New size: 5; reason: cpu resource utilization (percentage of request) above target
  Normal   SuccessfulRescale             96s                    horizontal-pod-autoscaler  New size: 4; reason: All metrics below target
  Normal   SuccessfulRescale             36s                    horizontal-pod-autoscaler  New size: 1; reason: All metrics below target
$ kubectl -n s13-hpa get events --sort-by=.lastTimestamp --field-selector involvedObject.kind=Deployment -o custom-columns=TIME:.lastTimestamp,REASON:.reason,MESSAGE:.message
TIME                   REASON              MESSAGE
2026-10-07T17:59:34Z   ScalingReplicaSet   Scaled up replica set hpa-demo-7f57cbc6f7 from 0 to 1
2026-10-07T18:01:02Z   ScalingReplicaSet   Scaled up replica set load-generator-848687b85f from 0 to 1
2026-10-07T18:02:44Z   ScalingReplicaSet   Scaled up replica set load-generator-848687b85f from 1 to 3
2026-10-07T18:02:52Z   ScalingReplicaSet   Scaled up replica set hpa-demo-7f57cbc6f7 from 1 to 2
2026-10-07T18:03:52Z   ScalingReplicaSet   Scaled up replica set hpa-demo-7f57cbc6f7 from 2 to 3
2026-10-07T18:04:52Z   ScalingReplicaSet   Scaled up replica set hpa-demo-7f57cbc6f7 from 3 to 5
2026-10-07T18:07:36Z   ScalingReplicaSet   Scaled down replica set hpa-demo-7f57cbc6f7 from 5 to 4
2026-10-07T18:08:36Z   ScalingReplicaSet   Scaled down replica set hpa-demo-7f57cbc6f7 from 4 to 1
```

### Timeline (local time, from the outputs above)

| Time | Load | HPA CPU | Replicas | What happened |
| :--- | :--- | :--- | :--- | :--- |
| 23:29:38 | none | `<unknown>` | 1 | HPA created, no metrics yet |
| 23:30:54 | none | 1% | 1 | first valid metric |
| 23:31:02 | 1 generator | 1% -> 48% | 1 | 48% is below 50% (within the 10% tolerance), no change |
| 23:32:44 | 3 generators | 58% | 1 -> 2 (23:32:52) | above target |
| 23:33:52 | | 116% | 2 -> 3 | |
| 23:34:52 | | 77% on 3 pods | 3 -> 5 | ceil(3 x 77/50) = 5, the maximum |
| 23:35:47 | stopped | 77% -> 48% -> 36% | 5 | the 60 s window keeps the highest recent recommendation |
| 23:37:36 | none | 36% | 5 -> 4 | |
| 23:38:36 | none | 0% | 4 -> 1 | back to `minReplicas` |

Scale-out took about 2 minutes from 1 to 5 Pods. It went in steps, because each decision waits for the next 60-second metrics sample. Scale-in started about 1m50s after the load stopped (one more metrics cycle plus my 60 s window) and finished one minute later.

### Note on my first attempt

In my first run the load generator used the Service DNS name (`wget http://hpa-demo-service`), as in the course command. Every request then made a DNS lookup, and the shared CoreDNS became the second-busiest pod on the node:

```bash
$ kubectl top pods -A --sort-by=cpu | head -15
NAMESPACE           NAME                                                CPU(cores)   MEMORY(bytes)   
s13-hpa             load-generator-85d698458c-vkw7p                     249m         2Mi             
s13-hpa             load-generator-85d698458c-kshtp                     249m         2Mi             
s13-hpa             load-generator-85d698458c-kdtpr                     248m         3Mi             
kube-system         coredns-559f6c778d-mb9q4                            207m         16Mi            
kube-system         kube-apiserver-minikube                             68m          484Mi           
s13-hpa             hpa-demo-7c899cf8f7-8x4dk                           43m          6Mi             
s13-hpa             hpa-demo-7c899cf8f7-px5qq                           43m          6Mi             
...
```

On a shared cluster that affects everyone, so I stopped that run and changed the generator to use the ClusterIP from the environment variable Kubernetes injects (`HPA_DEMO_SERVICE_SERVICE_HOST`), with five URLs per `wget` call. In the second run (shown above) CoreDNS stayed at 2m.

## Task 3: Mini project (production-ready web app)

The course mini project ([03-mini-project/COURSE-INSTRUCTIONS.md](03-mini-project/COURSE-INSTRUCTIONS.md)) combines a PVC mounted at `/data`, an HPA (2-5 replicas at 50% CPU) and all three probes on an nginx Deployment. I used the course files unchanged except for the namespace (`production-webapp` -> `s13-production-webapp`) and the image mirror.

Probes in [deployment.yaml](03-mini-project/deployment.yaml):

| Probe | Check | Settings | On failure |
| :--- | :--- | :--- | :--- |
| startupProbe | `GET /` on port 80 | every 2 s, up to 30 failures (60 s to start) | container restarted. Liveness and readiness only start after it succeeds |
| readinessProbe | `GET /` | after 5 s, every 5 s, timeout 2 s, 2 failures | Pod marked NotReady and removed from the Service endpoints, no restart |
| livenessProbe | `GET /` | after 5 s, every 5 s, timeout 2 s, 3 failures | container killed and restarted |

### Step 5.1-5.4: namespace, PVC, Deployment + Service, HPA

```bash
$ kubectl apply -f namespace.yaml
namespace/s13-production-webapp created
$ kubectl apply -f pvc.yaml
persistentvolumeclaim/web-data created
$ kubectl get pvc -n s13-production-webapp
NAME       STATUS   VOLUME                                     CAPACITY   ACCESS MODES   STORAGECLASS   VOLUMEATTRIBUTESCLASS   AGE
web-data   Bound    pvc-ec7a8554-e1de-49d8-b725-e97f2db9fc3f   500Mi      RWO            standard       <unset>                 3s
$ kubectl apply -f deployment.yaml
deployment.apps/web-app created
$ kubectl apply -f service.yaml
service/web-service created
$ kubectl -n s13-production-webapp rollout status deploy/web-app --timeout=180s
Waiting for deployment "web-app" rollout to finish: 0 of 2 updated replicas are available...
Waiting for deployment "web-app" rollout to finish: 1 of 2 updated replicas are available...
deployment "web-app" successfully rolled out
$ kubectl get pods -n s13-production-webapp -o wide
NAME                       READY   STATUS    RESTARTS   AGE   IP            NODE       NOMINATED NODE   READINESS GATES
web-app-76756f77bf-72zzv   1/1     Running   0          9s    10.244.0.19   minikube   <none>           <none>
web-app-76756f77bf-nnql4   1/1     Running   0          9s    10.244.0.18   minikube   <none>           <none>
$ kubectl get svc,endpointslices -n s13-production-webapp
NAME                  TYPE        CLUSTER-IP     EXTERNAL-IP   PORT(S)   AGE
service/web-service   ClusterIP   10.100.113.8   <none>        80/TCP    9s

NAME                                               ADDRESSTYPE   PORTS   ENDPOINTS                 AGE
endpointslice.discovery.k8s.io/web-service-6x2gd   IPv4          80      10.244.0.18,10.244.0.19   9s
$ kubectl apply -f hpa.yaml
horizontalpodautoscaler.autoscaling/web-app-hpa created
$ date +%H:%M:%S; kubectl get hpa -n s13-production-webapp
23:51:36
NAME          REFERENCE            TARGETS       MINPODS   MAXPODS   REPLICAS   AGE
web-app-hpa   Deployment/web-app   cpu: 1%/50%   2         5         2          2m1s
$ kubectl describe pod -n s13-production-webapp -l app=web-app | grep -E "^Name:|Liveness:|Readiness:|Startup:|Mounts:|/data from|ClaimName:" | head -8
Name:             web-app-76756f77bf-72zzv
    Liveness:     http-get http://:80/ delay=5s timeout=2s period=5s successThreshold=1 failureThreshold=3
    Readiness:    http-get http://:80/ delay=5s timeout=2s period=5s successThreshold=1 failureThreshold=2
    Startup:      http-get http://:80/ delay=0s timeout=1s period=2s successThreshold=1 failureThreshold=30
    Mounts:
      /data from persistent-storage (rw)
    ClaimName:  web-data
Name:             web-app-76756f77bf-nnql4
```

The PVC was provisioned dynamically by the default `standard` class. The PVC is `ReadWriteOnce`, and both replicas mount it. That works here because RWO means "one node", and minikube has only one node. On a multi-node cluster, Pods on a second node could not attach the volume, so a shared volume would need `ReadWriteMany` (NFS, EFS, Filestore), or each replica would get its own disk through a StatefulSet. The course also uses `strategy: Recreate`, so the old Pod releases the volume before the new one starts.

### Verification task 1: storage persistence

```bash
$ POD_NAME=$(kubectl get pods -n s13-production-webapp -l app=web-app -o jsonpath="{.items[0].metadata.name}"); echo "POD_NAME=$POD_NAME"
kubectl exec -n s13-production-webapp "$POD_NAME" -- sh -c "echo \"Student: Vansh Srivastava (24bcs10567)\" > /data/student.txt"
kubectl exec -n s13-production-webapp "$POD_NAME" -- cat /data/student.txt
POD_NAME=web-app-76756f77bf-72zzv
Student: Vansh Srivastava (24bcs10567)
$ OTHER=$(kubectl get pods -n s13-production-webapp -l app=web-app -o jsonpath="{.items[1].metadata.name}"); echo "other replica: $OTHER"; kubectl exec -n s13-production-webapp "$OTHER" -- cat /data/student.txt
other replica: web-app-76756f77bf-nnql4
Student: Vansh Srivastava (24bcs10567)
$ kubectl delete pod -n s13-production-webapp $(kubectl get pods -n s13-production-webapp -l app=web-app -o jsonpath="{.items[0].metadata.name}")
pod "web-app-76756f77bf-72zzv" deleted from s13-production-webapp namespace
$ kubectl -n s13-production-webapp wait --for=condition=Ready pod -l app=web-app --timeout=120s; kubectl get pods -n s13-production-webapp
pod/web-app-76756f77bf-89nk5 condition met
pod/web-app-76756f77bf-nnql4 condition met
NAME                       READY   STATUS    RESTARTS   AGE
web-app-76756f77bf-89nk5   1/1     Running   0          9s
web-app-76756f77bf-nnql4   1/1     Running   0          2m30s
$ for p in $(kubectl get pods -n s13-production-webapp -l app=web-app -o name); do echo "$p: $(kubectl exec -n s13-production-webapp $p -- cat /data/student.txt)"; done
pod/web-app-76756f77bf-89nk5: Student: Vansh Srivastava (24bcs10567)
pod/web-app-76756f77bf-nnql4: Student: Vansh Srivastava (24bcs10567)
```

The file written in one Pod is visible in the other replica (same volume), and the replacement Pod `89nk5` still has it.

### Verification task 2: Service

```bash
$ kubectl port-forward -n s13-production-webapp svc/web-service 18230:80 &   # left running in the background
Forwarding from 127.0.0.1:18230 -> 80
Forwarding from [::1]:18230 -> 80
$ curl -s http://localhost:18230 | head -5
<!DOCTYPE html>
<html>
<head>
<title>Welcome to nginx!</title>
<style>
```

![web-service through kubectl port-forward on localhost:18230](screenshots/01-mini-project-web-service.png)

### Verification task 3: HPA elastic scaling (default scale-down behaviour)

I used [03-mini-project/load-generator.yaml](03-mini-project/load-generator.yaml), the course `kubectl run load-generator` command as a Pod manifest. It is limited to 1 CPU and calls the Service by ClusterIP.

```bash
$ date +%H:%M:%S
23:52:25
$ kubectl apply -f load-generator.yaml
pod/load-generator created
$ kubectl -n s13-production-webapp wait --for=condition=Ready pod/load-generator --timeout=60s && kubectl -n s13-production-webapp logs load-generator
pod/load-generator condition met
sending requests to http://10.100.113.8:80/
```

A watch loop (`while true; do date; kubectl get hpa; kubectl get pods -l app=web-app; kubectl top pods; sleep 20; done`) recorded this. Excerpts:

```text
===== 23:52:25 =====
web-app-hpa   Deployment/web-app   cpu: 1%/50%   2     5     2     2m50s
web-app-76756f77bf-89nk5   1/1   Running   0     38s
web-app-76756f77bf-nnql4   1/1   Running   0     2m59s
web-app-76756f77bf-nnql4   1m    5Mi   
...
===== 23:53:45 =====
web-app-hpa   Deployment/web-app   cpu: 64%/50%   2     5     2     4m10s
web-app-76756f77bf-89nk5   1/1   Running   0     118s
web-app-76756f77bf-f8x99   1/1   Running   0     11s
web-app-76756f77bf-nnql4   1/1   Running   0     4m19s
load-generator             920m   11Mi   
web-app-76756f77bf-89nk5   59m    6Mi    
web-app-76756f77bf-nnql4   69m    6Mi    
===== 23:54:05 =====
web-app-hpa   Deployment/web-app   cpu: 64%/50%   2     5     3     4m31s
web-app-76756f77bf-89nk5   1/1   Running   0     2m19s
web-app-76756f77bf-f8x99   1/1   Running   0     32s
web-app-76756f77bf-nnql4   1/1   Running   0     4m40s
load-generator             920m   11Mi   
web-app-76756f77bf-89nk5   59m    6Mi    
web-app-76756f77bf-nnql4   69m    6Mi    
...
===== 23:57:27 =====
web-app-hpa   Deployment/web-app   cpu: 40%/50%   2     5     3     7m52s
web-app-76756f77bf-89nk5   1/1   Running   0     5m40s
web-app-76756f77bf-f8x99   1/1   Running   0     3m53s
web-app-76756f77bf-nnql4   1/1   Running   0     8m1s
web-app-76756f77bf-89nk5   40m   6Mi   
web-app-76756f77bf-f8x99   41m   6Mi   
web-app-76756f77bf-nnql4   40m   6Mi   
===== 23:57:47 =====
web-app-hpa   Deployment/web-app   cpu: 1%/50%   2     5     3     8m12s
web-app-76756f77bf-89nk5   1/1   Running   0     6m
web-app-76756f77bf-f8x99   1/1   Running   0     4m13s
web-app-76756f77bf-nnql4   1/1   Running   0     8m21s
web-app-76756f77bf-89nk5   1m    5Mi   
web-app-76756f77bf-f8x99   1m    5Mi   
web-app-76756f77bf-nnql4   2m    5Mi   
...
===== 00:02:29 =====
web-app-hpa   Deployment/web-app   cpu: 1%/50%   2     5     3     12m
web-app-76756f77bf-89nk5   1/1   Running   0     10m
web-app-76756f77bf-nnql4   1/1   Running   0     13m
web-app-76756f77bf-89nk5   1m    5Mi   
web-app-76756f77bf-nnql4   1m    5Mi   
===== 00:02:49 =====
web-app-hpa   Deployment/web-app   cpu: 1%/50%   2     5     2     13m
web-app-76756f77bf-89nk5   1/1   Running   0     11m
web-app-76756f77bf-nnql4   1/1   Running   0     13m
web-app-76756f77bf-89nk5   1m    5Mi   
web-app-76756f77bf-nnql4   1m    5Mi   
```

```bash
$ date +%H:%M:%S; kubectl get hpa -n s13-production-webapp
23:55:55
NAME          REFERENCE            TARGETS        MINPODS   MAXPODS   REPLICAS   AGE
web-app-hpa   Deployment/web-app   cpu: 40%/50%   2         5         3          6m20s
$ kubectl top pods -n s13-production-webapp
NAME                       CPU(cores)   MEMORY(bytes)   
load-generator             919m         12Mi            
web-app-76756f77bf-89nk5   40m          6Mi             
web-app-76756f77bf-f8x99   38m          6Mi             
web-app-76756f77bf-nnql4   43m          6Mi             
$ date +%H:%M:%S
23:55:55
$ kubectl delete pod load-generator -n s13-production-webapp
pod "load-generator" deleted from s13-production-webapp namespace
```

Observed:

- 23:53:45: 64% on 2 Pods, so the HPA scaled to ceil(2 x 64/50) = 3 Pods. With 3 Pods the average dropped to 40-48%, under the target, so it stayed at 3.
- 23:55:55: load stopped. 23:57:47: CPU down to 1%.
- 00:02:49: scaled back to 2 (`minReplicas`). This HPA has no `behavior` block, so the default 300 s scale-down stabilization window applies: the HPA waited 5 minutes of low recommendations before removing a Pod. The course README describes exactly this ("After the 5-minute stabilization window..."). The Task 2 HPA, with its 60 s window, scaled in within about a minute.

### Probe challenges (course "Bonus Challenges" 2 and 3)

**Readiness gating:** readiness path changed to `/does-not-exist`:

```bash
$ kubectl -n s13-production-webapp patch deploy web-app --type=json -p '[{"op":"replace","path":"/spec/template/spec/containers/0/readinessProbe/httpGet/path","value":"/does-not-exist"}]'
deployment.apps/web-app patched
...
$ kubectl -n s13-production-webapp run probe-check --rm -i --restart=Never --image=public.ecr.aws/docker/library/busybox:1.36 -- wget -T 3 -qO- http://web-service 2>&1 | tail -2
pod "probe-check" deleted from s13-production-webapp namespace
pod s13-production-webapp/probe-check terminated (Error)
$ kubectl -n s13-production-webapp get pods -l app=web-app
NAME                       READY   STATUS    RESTARTS   AGE
web-app-7b9c6fd488-4z4wk   0/1     Running   0          50s
web-app-7b9c6fd488-f4gkw   0/1     Running   0          50s
$ kubectl -n s13-production-webapp get endpointslices -l kubernetes.io/service-name=web-service -o jsonpath='{range .items[*].endpoints[*]}{.addresses[0]} ready={.conditions.ready}{"\n"}{end}'
10.244.0.44 ready=false
10.244.0.45 ready=false
$ kubectl -n s13-production-webapp get endpoints web-service
Warning: v1 Endpoints is deprecated in v1.33+; use discovery.k8s.io/v1 EndpointSlice
NAME          ENDPOINTS   AGE
web-service               4d1h
$ kubectl -n s13-production-webapp events --types=Warning | tail -3
4s (x6 over 4d1h)      Warning   FailedComputeMetricsReplicas   HorizontalPodAutoscaler/web-app-hpa   invalid metrics (1 invalid out of 1), first error is: failed to get cpu resource metric value: failed to get cpu utilization: did not receive metrics for targeted pods (pods might be unready)
0s (x9 over 40s)       Warning   Unhealthy                      Pod/web-app-7b9c6fd488-4z4wk          Readiness probe failed: HTTP probe failed with statuscode: 404
0s (x9 over 40s)       Warning   Unhealthy                      Pod/web-app-7b9c6fd488-f4gkw          Readiness probe failed: HTTP probe failed with statuscode: 404
```

The Pods are `Running` but `0/1` Ready. The EndpointSlice still lists their IPs but with `ready=false`, so the Service has no usable endpoints (`kubectl get endpoints` is empty) and a request from inside the namespace failed. There were no restarts: a readiness failure only takes the Pod out of traffic. The HPA also stopped working ("pods might be unready"), because it ignores unready Pods. And because the course Deployment uses `strategy: Recreate`, both old Pods were killed before the new ones came up, so this config change caused a full outage. With `RollingUpdate`, the rollout would have stopped at the first NotReady Pod and the old Pods would have kept serving.

Revert:

```bash
$ kubectl apply -f deployment.yaml
deployment.apps/web-app configured
$ kubectl -n s13-production-webapp rollout status deploy/web-app --timeout=120s
Waiting for deployment "web-app" rollout to finish: 0 out of 2 new replicas have been updated...
...
Waiting for deployment "web-app" rollout to finish: 1 of 2 updated replicas are available...
deployment "web-app" successfully rolled out
$ kubectl -n s13-production-webapp get pods -l app=web-app; kubectl -n s13-production-webapp get endpoints web-service 2>/dev/null
NAME                       READY   STATUS    RESTARTS   AGE
web-app-76756f77bf-ng65g   1/1     Running   0          9s
web-app-76756f77bf-rmx4l   1/1     Running   0          9s
NAME          ENDPOINTS                       AGE
web-service   10.244.0.47:80,10.244.0.48:80   4d1h
```

**Liveness restart loop:** liveness path changed to `/crash`:

```bash
$ kubectl -n s13-production-webapp patch deploy web-app --type=json -p '[{"op":"replace","path":"/spec/template/spec/containers/0/livenessProbe/httpGet/path","value":"/crash"}]'
deployment.apps/web-app patched
$ kubectl -n s13-production-webapp get pods -l app=web-app
NAME                      READY   STATUS    RESTARTS     AGE
web-app-7b7767f4b-h8bxh   0/1     Running   4 (9s ago)   75s
web-app-7b7767f4b-vxlpj   0/1     Running   4 (9s ago)   75s
$ kubectl -n s13-production-webapp events --types=Warning,Normal | grep -E 'Liveness probe failed|failed liveness probe' | tail -3
10s (x12 over 69s)     Warning   Unhealthy                      Pod/web-app-7b7767f4b-h8bxh           Liveness probe failed: HTTP probe failed with statuscode: 404
10s (x4 over 59s)      Normal    Killing                        Pod/web-app-7b7767f4b-h8bxh           Container nginx failed liveness probe, will be restarted
10s (x12 over 69s)     Warning   Unhealthy                      Pod/web-app-7b7767f4b-vxlpj           Liveness probe failed: HTTP probe failed with statuscode: 404
$ kubectl -n s13-production-webapp describe pod -l app=web-app | grep -E '^Name:|Restart Count|Last State|Reason:|Exit Code' | head -6
Name:             web-app-7b7767f4b-h8bxh
    Last State:     Terminated
      Reason:       Completed
      Exit Code:    0
    Restart Count:  4
Name:             web-app-7b7767f4b-vxlpj
```

After the startup probe passes, three liveness failures 5 s apart (about 15 s) make the kubelet restart the container. In 75 seconds each Pod was restarted 4 times. They also never become Ready again, because readiness is only checked once a new container has passed its startup probe. Revert, and the data on the PVC is still there:

```bash
$ kubectl apply -f deployment.yaml
deployment.apps/web-app configured
$ kubectl -n s13-production-webapp rollout status deploy/web-app --timeout=120s
Waiting for deployment "web-app" rollout to finish: 0 out of 2 new replicas have been updated...
...
Waiting for deployment "web-app" rollout to finish: 1 of 2 updated replicas are available...
deployment "web-app" successfully rolled out
$ kubectl -n s13-production-webapp get pods -l app=web-app
NAME                       READY   STATUS    RESTARTS   AGE
web-app-76756f77bf-ghrsk   1/1     Running   0          8s
web-app-76756f77bf-wr74n   1/1     Running   0          8s
$ for p in $(kubectl get pods -n s13-production-webapp -l app=web-app -o name); do echo "$p: $(kubectl exec -n s13-production-webapp $p -- cat /data/student.txt)"; done
pod/web-app-76756f77bf-ghrsk: Student: Vansh Srivastava (24bcs10567)
pod/web-app-76756f77bf-wr74n: Student: Vansh Srivastava (24bcs10567)
```

### Answers to the course troubleshooting guide

- **PVC stuck in Pending:** did not happen here (the default `standard` class exists). In Task 1 I saw a related case: a `WaitForFirstConsumer` claim stayed Pending because the provisioner was not allowed to read Nodes. `kubectl describe pvc` showed the reason.
- **HPA shows `<unknown>/50%`:** seen at the start of Task 2. The cause was timing (60 s metrics resolution and new Pods), not a missing CPU request. A missing `resources.requests.cpu` gives the same symptom permanently.
- **Restarts caused by probes:** reproduced with the `/crash` liveness path. `kubectl describe` / `kubectl events` show `Liveness probe failed: HTTP probe failed with statuscode: 404` followed by `Container nginx failed liveness probe, will be restarted`.

## Cleanup

```bash
$ kubectl delete namespace s13-hpa s13-production-webapp
namespace "s13-hpa" deleted
namespace "s13-production-webapp" deleted
```

The volume demo's cluster-scoped objects (PV, StorageClass, ClusterRole/Binding) and its node directories were removed earlier (see the Task 1 README). The port-forward and watch loops were stopped.

## What I learned

- Volume lifetime is the main choice: emptyDir lasts as long as the Pod, hostPath as long as the node, a PV is independent. A PVC hides which PV is used, and with a default StorageClass a PVC without `storageClassName` is provisioned dynamically, even if a matching hand-made PV exists.
- `WaitForFirstConsumer` delays volume creation until a Pod is scheduled. It depends on the provisioner being able to read the chosen Node, which the minikube provisioner cannot do by default.
- The HPA works on usage divided by **request**. It reacts in steps tied to the metrics-server interval (60 s here), scales up quickly, and scales down only after the stabilization window (300 s default, 60 s in my HPA).
- A load generator is also a client of shared services. Using the DNS name for every request put real load on CoreDNS.
- Startup, readiness and liveness answer different questions. Readiness failure removes a Pod from the Service without a restart, liveness failure restarts it, and with `Recreate` a broken readiness probe takes the whole app offline.
