# Task 2: Helm Rollback

In this part I went through the full rollback workflow from the brief: **Install -> Upgrade -> Verify -> Upgrade again -> Verify -> Rollback -> Verify**. I wrote a small chart for it, `rollback-demo`, in which every revision is clearly different: a different nginx image tag, a different message and page colour (from a ConfigMap), and a different replica count. After each step I checked `helm history`, the image that is really running, and the response of the app through `kubectl port-forward` and curl. At the end I also tried an upgrade that fails, to see Helm roll back on its own.

- Namespace: `s15-rollback`, release: `s15-rollback-demo`
- Host port for port-forward: `18310` (`18311` for the screenshots)

Back to the session overview: [../README.md](../README.md)

## Files

```text
02-rollback/
├── rollback-demo/              the chart
│   ├── Chart.yaml
│   ├── values.yaml             defaults = revision 1 (nginx 1.26, 1 replica, "version 1", blue)
│   └── templates/
│       ├── configmap.yaml      index.html + version.txt built from the values
│       ├── deployment.yaml     nginx, mounts the ConfigMap, checksum annotation, small resources
│       ├── service.yaml        ClusterIP service on port 80
│       └── NOTES.txt           prints the revision, image and how to port-forward
├── values-v2.yaml              revision 2 (nginx 1.27, 2 replicas, "version 2", green)
├── values-v3.yaml              revision 3 (nginx 1.28, 3 replicas, "version 3", yellow)
└── verify.sh                   prints history, running image, pods, and curls the app
```

What changes between the revisions:

| Revision | Command | Image | Replicas | Page message | Colour |
|----------|---------|-------|----------|--------------|--------|
| 1 | `helm install` (chart defaults) | `nginx:1.26-alpine` | 1 | Hello from version 1 | blue |
| 2 | `helm upgrade -f values-v2.yaml` | `nginx:1.27-alpine` | 2 | Hello from version 2 | green |
| 3 | `helm upgrade -f values-v3.yaml` | `nginx:1.28-alpine` | 3 | Hello from version 3 | yellow |
| 4 | `helm rollback ... 2` | `nginx:1.27-alpine` | 2 | Hello from version 2 | green |

The images come from `public.ecr.aws/docker/library/nginx`, which mirrors the official Docker Hub image. Docker Hub returned `429 Too Many Requests` on this machine (see Task 1).

### Important parts of the chart

`templates/configmap.yaml` builds two files from the values. `version.txt` is easy to check with curl:

```yaml
  version.txt: |
    version={{ .Values.app.version }}
    message={{ .Values.app.message }}
    image={{ .Values.image.repository }}:{{ .Values.image.tag }}
    replicas={{ .Values.replicaCount }}
    renderedInRevision={{ .Release.Revision }}
```

`templates/deployment.yaml` mounts that ConfigMap over `/usr/share/nginx/html` and has a checksum annotation. When only the message changes, the pod template still changes, so Kubernetes replaces the pods:

```yaml
      annotations:
        checksum/config: {{ include (print $.Template.BasePath "/configmap.yaml") . | sha256sum }}
```

### verify.sh

[`verify.sh`](verify.sh) does the same checks after every step, so the outputs can be compared:

1. waits for `kubectl rollout status` and for old pods to finish stopping,
2. `helm history` (which revision is deployed),
3. the image and ready replicas of the Deployment, and the image of every pod,
4. starts `kubectl port-forward svc/s15-rollback-demo-web 18310:80` in the background, runs `curl /version.txt` and `curl -I` (the `Server:` header shows the real nginx version in the container), and stops the port-forward again.

## Step 1: Install (revision 1)

```bash
$ helm install s15-rollback-demo ./rollback-demo -n s15-rollback --create-namespace --wait --timeout 3m
NAME: s15-rollback-demo
LAST DEPLOYED: Wed Oct  7 23:23:33 2026
NAMESPACE: s15-rollback
STATUS: deployed
REVISION: 1
DESCRIPTION: Install complete
TEST SUITE: None
NOTES:
s15-rollback-demo (Helm revision 1) runs app v1
with public.ecr.aws/docker/library/nginx:1.26-alpine and 1 replica(s).

Check it:
  kubectl port-forward -n s15-rollback svc/s15-rollback-demo-web 18310:80
  curl http://localhost:18310/version.txt
```

### Verify revision 1

```bash
$ ./verify.sh
$ helm history s15-rollback-demo -n s15-rollback
REVISION  UPDATED                   STATUS    CHART                APP VERSION  DESCRIPTION
1         Wed Oct  7 23:23:33 2026  deployed  rollback-demo-0.1.0  1.0          Install complete

$ kubectl get deploy s15-rollback-demo-web -n s15-rollback -o jsonpath='{.spec.template.spec.containers[0].image}{"  replicas="}{.status.readyReplicas}{"\n"}'
public.ecr.aws/docker/library/nginx:1.26-alpine  replicas=1

$ kubectl get pods -n s15-rollback -l app.kubernetes.io/instance=s15-rollback-demo -o custom-columns=POD:.metadata.name,IMAGE:.spec.containers[0].image,PHASE:.status.phase
POD                                      IMAGE                                             PHASE
s15-rollback-demo-web-7b4b9fb98d-q2jq2   public.ecr.aws/docker/library/nginx:1.26-alpine   Running

$ curl -s http://localhost:18310/version.txt
version=v1
message=Hello from version 1
image=public.ecr.aws/docker/library/nginx:1.26-alpine
replicas=1
renderedInRevision=1

$ curl -sI http://localhost:18310/ | grep Server
Server: nginx/1.26.3
```

Revision 1 is `deployed`. One pod runs `nginx:1.26-alpine`, the app returns `version=v1`, and the `Server` header confirms nginx 1.26.3 is really running.

![Revision 1: version 1, nginx 1.26, 1 replica](../screenshots/01-rollback-rev1-v1.png)

## Step 2: Upgrade (revision 2)

```bash
$ helm upgrade s15-rollback-demo ./rollback-demo -n s15-rollback -f values-v2.yaml --wait --timeout 3m
Release "s15-rollback-demo" has been upgraded. Happy Helming!
NAME: s15-rollback-demo
LAST DEPLOYED: Wed Oct  7 23:23:57 2026
NAMESPACE: s15-rollback
STATUS: deployed
REVISION: 2
DESCRIPTION: Upgrade complete
TEST SUITE: None
NOTES:
s15-rollback-demo (Helm revision 2) runs app v2
with public.ecr.aws/docker/library/nginx:1.27-alpine and 2 replica(s).

Check it:
  kubectl port-forward -n s15-rollback svc/s15-rollback-demo-web 18310:80
  curl http://localhost:18310/version.txt
```

### Verify revision 2

```bash
$ ./verify.sh
$ helm history s15-rollback-demo -n s15-rollback
REVISION  UPDATED                   STATUS      CHART                APP VERSION  DESCRIPTION
1         Wed Oct  7 23:23:33 2026  superseded  rollback-demo-0.1.0  1.0          Install complete
2         Wed Oct  7 23:23:57 2026  deployed    rollback-demo-0.1.0  1.0          Upgrade complete

$ kubectl get deploy s15-rollback-demo-web -n s15-rollback -o jsonpath='{.spec.template.spec.containers[0].image}{"  replicas="}{.status.readyReplicas}{"\n"}'
public.ecr.aws/docker/library/nginx:1.27-alpine  replicas=2

$ kubectl get pods -n s15-rollback -l app.kubernetes.io/instance=s15-rollback-demo -o custom-columns=POD:.metadata.name,IMAGE:.spec.containers[0].image,PHASE:.status.phase
POD                                     IMAGE                                             PHASE
s15-rollback-demo-web-cf698bdcd-6rwwz   public.ecr.aws/docker/library/nginx:1.27-alpine   Running
s15-rollback-demo-web-cf698bdcd-qnpd2   public.ecr.aws/docker/library/nginx:1.27-alpine   Running

$ curl -s http://localhost:18310/version.txt
version=v2
message=Hello from version 2
image=public.ecr.aws/docker/library/nginx:1.27-alpine
replicas=2
renderedInRevision=2

$ curl -sI http://localhost:18310/ | grep Server
Server: nginx/1.27.5

$ helm get values s15-rollback-demo -n s15-rollback
USER-SUPPLIED VALUES:
app:
  color: '#dcfce7'
  message: Hello from version 2
  version: v2
image:
  tag: 1.27-alpine
replicaCount: 2
```

Revision 1 is now `superseded` and revision 2 is `deployed`. Two pods run `nginx:1.27-alpine`, the page says version 2, and nginx reports 1.27.5. `helm get values` shows exactly what `values-v2.yaml` set.

![Revision 2: version 2, nginx 1.27, 2 replicas](../screenshots/02-rollback-rev2-v2.png)

## Step 3: Upgrade again (revision 3)

```bash
$ helm upgrade s15-rollback-demo ./rollback-demo -n s15-rollback -f values-v3.yaml --wait --timeout 3m
Release "s15-rollback-demo" has been upgraded. Happy Helming!
NAME: s15-rollback-demo
LAST DEPLOYED: Wed Oct  7 23:24:10 2026
NAMESPACE: s15-rollback
STATUS: deployed
REVISION: 3
DESCRIPTION: Upgrade complete
TEST SUITE: None
NOTES:
s15-rollback-demo (Helm revision 3) runs app v3
with public.ecr.aws/docker/library/nginx:1.28-alpine and 3 replica(s).

Check it:
  kubectl port-forward -n s15-rollback svc/s15-rollback-demo-web 18310:80
  curl http://localhost:18310/version.txt
```

### Verify revision 3

```bash
$ ./verify.sh
$ helm history s15-rollback-demo -n s15-rollback
REVISION  UPDATED                   STATUS      CHART                APP VERSION  DESCRIPTION
1         Wed Oct  7 23:23:33 2026  superseded  rollback-demo-0.1.0  1.0          Install complete
2         Wed Oct  7 23:23:57 2026  superseded  rollback-demo-0.1.0  1.0          Upgrade complete
3         Wed Oct  7 23:24:10 2026  deployed    rollback-demo-0.1.0  1.0          Upgrade complete

$ kubectl get deploy s15-rollback-demo-web -n s15-rollback -o jsonpath='{.spec.template.spec.containers[0].image}{"  replicas="}{.status.readyReplicas}{"\n"}'
public.ecr.aws/docker/library/nginx:1.28-alpine  replicas=3

$ kubectl get pods -n s15-rollback -l app.kubernetes.io/instance=s15-rollback-demo -o custom-columns=POD:.metadata.name,IMAGE:.spec.containers[0].image,PHASE:.status.phase
POD                                     IMAGE                                             PHASE
s15-rollback-demo-web-95c4486b6-dg2dr   public.ecr.aws/docker/library/nginx:1.28-alpine   Running
s15-rollback-demo-web-95c4486b6-ftdhg   public.ecr.aws/docker/library/nginx:1.28-alpine   Running
s15-rollback-demo-web-95c4486b6-xndw2   public.ecr.aws/docker/library/nginx:1.28-alpine   Running

$ curl -s http://localhost:18310/version.txt
version=v3
message=Hello from version 3
image=public.ecr.aws/docker/library/nginx:1.28-alpine
replicas=3
renderedInRevision=3

$ curl -sI http://localhost:18310/ | grep Server
Server: nginx/1.28.3
```

Three pods on `nginx:1.28-alpine`, the app says version 3, and nginx is 1.28.3.

![Revision 3: version 3, nginx 1.28, 3 replicas](../screenshots/03-rollback-rev3-v3.png)

## Step 4: Rollback to revision 2

Say version 3 is bad and I want version 2 back:

```bash
$ helm rollback s15-rollback-demo 2 -n s15-rollback --wait --timeout 3m
Rollback was a success! Happy Helming!
```

### Verify after the rollback

```bash
$ ./verify.sh
$ helm history s15-rollback-demo -n s15-rollback
REVISION  UPDATED                   STATUS      CHART                APP VERSION  DESCRIPTION
1         Wed Oct  7 23:23:33 2026  superseded  rollback-demo-0.1.0  1.0          Install complete
2         Wed Oct  7 23:23:57 2026  superseded  rollback-demo-0.1.0  1.0          Upgrade complete
3         Wed Oct  7 23:24:10 2026  superseded  rollback-demo-0.1.0  1.0          Upgrade complete
4         Wed Oct  7 23:24:25 2026  deployed    rollback-demo-0.1.0  1.0          Rollback to 2

$ kubectl get deploy s15-rollback-demo-web -n s15-rollback -o jsonpath='{.spec.template.spec.containers[0].image}{"  replicas="}{.status.readyReplicas}{"\n"}'
public.ecr.aws/docker/library/nginx:1.27-alpine  replicas=2

$ kubectl get pods -n s15-rollback -l app.kubernetes.io/instance=s15-rollback-demo -o custom-columns=POD:.metadata.name,IMAGE:.spec.containers[0].image,PHASE:.status.phase
POD                                     IMAGE                                             PHASE
s15-rollback-demo-web-cf698bdcd-kk4sk   public.ecr.aws/docker/library/nginx:1.27-alpine   Running
s15-rollback-demo-web-cf698bdcd-rggz5   public.ecr.aws/docker/library/nginx:1.27-alpine   Running

$ curl -s http://localhost:18310/version.txt
version=v2
message=Hello from version 2
image=public.ecr.aws/docker/library/nginx:1.27-alpine
replicas=2
renderedInRevision=2

$ curl -sI http://localhost:18310/ | grep Server
Server: nginx/1.27.5

$ helm get values s15-rollback-demo -n s15-rollback
USER-SUPPLIED VALUES:
app:
  color: '#dcfce7'
  message: Hello from version 2
  version: v2
image:
  tag: 1.27-alpine
replicaCount: 2

$ kubectl get configmap s15-rollback-demo-content -n s15-rollback -o jsonpath="{.data.version\.txt}"
version=v2
message=Hello from version 2
image=public.ecr.aws/docker/library/nginx:1.27-alpine
replicas=2
renderedInRevision=2
```

![After the rollback (revision 4): version 2 again, nginx 1.27, 2 replicas](../screenshots/04-rollback-rev4-back-to-v2.png)

All three changes went back to their revision 2 state: the image is `nginx:1.27-alpine` again (nginx 1.27.5 answers), there are 2 replicas, and the message and colour are version 2.

Things I noticed:

- **A rollback is a new revision.** Helm did not delete revision 3 or move back to number 2. It created revision 4 with the description `Rollback to 2`, so the history keeps a full record of what happened.
- **Helm re-applies the saved manifest and does not render the chart again.** The page still says `renderedInRevision=2`, even though the release is at revision 4. Helm took the manifest it had saved for revision 2 and applied it as it was.
- **Kubernetes reused the old ReplicaSet.** The pod names after the rollback start with `cf698bdcd`, the same pod-template hash as in revision 2. The Deployment just scaled that ReplicaSet back up:

```bash
$ kubectl get rs -n s15-rollback -o wide
NAME                               DESIRED   CURRENT   READY   AGE   CONTAINERS   IMAGES                                            SELECTOR
s15-rollback-demo-web-7b4b9fb98d   0         0         0       67s   web          public.ecr.aws/docker/library/nginx:1.26-alpine   app.kubernetes.io/instance=s15-rollback-demo,app.kubernetes.io/name=rollback-demo,pod-template-hash=7b4b9fb98d
s15-rollback-demo-web-95c4486b6    0         0         0       30s   web          public.ecr.aws/docker/library/nginx:1.28-alpine   app.kubernetes.io/instance=s15-rollback-demo,app.kubernetes.io/name=rollback-demo,pod-template-hash=95c4486b6
s15-rollback-demo-web-cf698bdcd    2         2         2       42s   web          public.ecr.aws/docker/library/nginx:1.27-alpine   app.kubernetes.io/instance=s15-rollback-demo,app.kubernetes.io/name=rollback-demo,pod-template-hash=cf698bdcd

$ kubectl get secrets -n s15-rollback -l owner=helm
NAME                                      TYPE                 DATA   AGE
sh.helm.release.v1.s15-rollback-demo.v1   helm.sh/release.v1   1      67s
sh.helm.release.v1.s15-rollback-demo.v2   helm.sh/release.v1   1      42s
sh.helm.release.v1.s15-rollback-demo.v3   helm.sh/release.v1   1      30s
sh.helm.release.v1.s15-rollback-demo.v4   helm.sh/release.v1   1      14s
```

Each Helm revision is stored as its own Secret (`...v1` to `...v4`). That is the data `helm history` and `helm rollback` read.

## Extra: automatic rollback when an upgrade fails

The course notes (`08-rollback`) also show `--atomic`, which rolls back by itself if the upgrade does not become healthy within the timeout. I tried it with an image tag that does not exist. Helm 4 still accepts `--atomic` but says it is deprecated, so I also ran the new name, `--rollback-on-failure`:

```bash
$ helm upgrade s15-rollback-demo ./rollback-demo -n s15-rollback -f values-v3.yaml --set image.tag=9.99-does-not-exist --atomic --timeout 60s
Flag --atomic has been deprecated, use --rollback-on-failure instead
level=WARN msg="upgrade failed" name=s15-rollback-demo error="resource Deployment/s15-rollback/s15-rollback-demo-web not ready. status: InProgress, message: Updated: 1/3\ncontext deadline exceeded"
Error: UPGRADE FAILED: release s15-rollback-demo failed, and has been rolled back due to rollback-on-failure being set: resource Deployment/s15-rollback/s15-rollback-demo-web not ready. status: InProgress, message: Updated: 1/3
context deadline exceeded

$ helm upgrade s15-rollback-demo ./rollback-demo -n s15-rollback -f values-v3.yaml --set image.tag=9.99-does-not-exist --rollback-on-failure --timeout 60s
level=WARN msg="upgrade failed" name=s15-rollback-demo error="resource Deployment/s15-rollback/s15-rollback-demo-web not ready. status: InProgress, message: Updated: 1/3\ncontext deadline exceeded"
Error: UPGRADE FAILED: release s15-rollback-demo failed, and has been rolled back due to rollback-on-failure being set: resource Deployment/s15-rollback/s15-rollback-demo-web not ready. status: InProgress, message: Updated: 1/3
context deadline exceeded
```

Both times Helm waited up to 60 seconds, saw that the Deployment never became ready (`Updated: 1/3`), marked that revision as `failed` and rolled back to the last good one:

```bash
$ ./verify.sh
$ helm history s15-rollback-demo -n s15-rollback
REVISION  UPDATED                   STATUS      CHART                APP VERSION  DESCRIPTION
1         Wed Oct  7 23:23:33 2026  superseded  rollback-demo-0.1.0  1.0          Install complete
2         Wed Oct  7 23:23:57 2026  superseded  rollback-demo-0.1.0  1.0          Upgrade complete
3         Wed Oct  7 23:24:10 2026  superseded  rollback-demo-0.1.0  1.0          Upgrade complete
4         Wed Oct  7 23:24:25 2026  superseded  rollback-demo-0.1.0  1.0          Rollback to 2
5         Wed Oct  7 23:24:46 2026  failed      rollback-demo-0.1.0  1.0          Upgrade "s15-rollback-demo" failed: resource Deployment/s15-rollback/s15-rollback-demo-web not ready. status: InProgress, message: Updated: ...
6         Wed Oct  7 23:25:46 2026  superseded  rollback-demo-0.1.0  1.0          Rollback to 4
7         Wed Oct  7 23:25:46 2026  failed      rollback-demo-0.1.0  1.0          Upgrade "s15-rollback-demo" failed: resource Deployment/s15-rollback/s15-rollback-demo-web not ready. status: InProgress, message: Updated: ...
8         Wed Oct  7 23:26:46 2026  deployed    rollback-demo-0.1.0  1.0          Rollback to 6

$ kubectl get deploy s15-rollback-demo-web -n s15-rollback -o jsonpath='{.spec.template.spec.containers[0].image}{"  replicas="}{.status.readyReplicas}{"\n"}'
public.ecr.aws/docker/library/nginx:1.27-alpine  replicas=2

$ kubectl get pods -n s15-rollback -l app.kubernetes.io/instance=s15-rollback-demo -o custom-columns=POD:.metadata.name,IMAGE:.spec.containers[0].image,PHASE:.status.phase
POD                                     IMAGE                                             PHASE
s15-rollback-demo-web-cf698bdcd-kk4sk   public.ecr.aws/docker/library/nginx:1.27-alpine   Running
s15-rollback-demo-web-cf698bdcd-rggz5   public.ecr.aws/docker/library/nginx:1.27-alpine   Running

$ curl -s http://localhost:18310/version.txt
version=v3
message=Hello from version 3
image=public.ecr.aws/docker/library/nginx:9.99-does-not-exist
replicas=3
renderedInRevision=7

$ curl -sI http://localhost:18310/ | grep Server
Server: nginx/1.27.5
```

The history now shows `5 failed`, `6 Rollback to 4`, `7 failed`, `8 Rollback to 6`. The Deployment is back on `nginx:1.27-alpine` with 2 replicas, and the old pods (`cf698bdcd-kk4sk`, `-rggz5`) were never replaced, so the app stayed up the whole time.

### Problem I found: the pods served the failed revision's page

`curl /version.txt` above still returned the **failed** revision 7 content (`version=v3`, `image=...:9.99-does-not-exist`), although Helm had rolled back and nginx was 1.27.5. So I compared the ConfigMap in the API with the file inside a running pod:

```bash
$ kubectl get configmap s15-rollback-demo-content -n s15-rollback -o jsonpath="{.data.version\.txt}"
version=v2
message=Hello from version 2
image=public.ecr.aws/docker/library/nginx:1.27-alpine
replicas=2
renderedInRevision=2

$ kubectl exec -n s15-rollback deploy/s15-rollback-demo-web -- cat /usr/share/nginx/html/version.txt
version=v3
message=Hello from version 3
image=public.ecr.aws/docker/library/nginx:9.99-does-not-exist
replicas=3
renderedInRevision=7

$ date
Wed Oct  7 23:27:00 IST 2026
```

The ConfigMap was correct (v2), but the file in the pod was still v3. This is how ConfigMap volumes work. The failed upgrade had updated the ConfigMap, and the kubelet copies ConfigMap changes into running pods' volumes **in place**, without restarting them. So the old, healthy pods picked up the v3 content while the new v3 pods could not even start. After the rollback, the kubelet needs one sync period to copy the v2 content back. I checked every 10 seconds:

```bash
$ for i in $(seq 1 24); do v=$(kubectl exec -n s15-rollback deploy/s15-rollback-demo-web -- head -1 /usr/share/nginx/html/version.txt 2>/dev/null); echo "$(date +%H:%M:%S) $v"; [ "$v" = "version=v2" ] && break; sleep 10; done
23:27:06 version=v3
23:27:17 version=v3
23:27:27 version=v3
23:27:37 version=v3
23:27:47 version=v3
23:27:57 version=v3
23:28:08 version=v2
```

About 80 seconds after the rollback (23:26:46 -> 23:28:08), the pod served v2 again:

```bash
$ for p in $(kubectl get pods -n s15-rollback -l app.kubernetes.io/instance=s15-rollback-demo -o name); do echo "$p: $(kubectl exec -n s15-rollback $p -- head -1 /usr/share/nginx/html/version.txt)"; done
pod/s15-rollback-demo-web-cf698bdcd-kk4sk: version=v2
pod/s15-rollback-demo-web-cf698bdcd-rggz5: version=v2

$ ./verify.sh 2>&1 | tail -9
$ curl -s http://localhost:18310/version.txt
version=v2
message=Hello from version 2
image=public.ecr.aws/docker/library/nginx:1.27-alpine
replicas=2
renderedInRevision=2

$ curl -sI http://localhost:18310/ | grep Server
Server: nginx/1.27.5
```

Lesson: if a mounted ConfigMap is updated in place, a failed upgrade can change what the old, healthy pods serve, and a rollback only fixes it after a delay. Ways to avoid it:

- mount the files with `subPath`, because the kubelet does not update subPath mounts in a running pod (I did this in the Task 3 chart and it worked, see [../03-mini-project/README.md](../03-mini-project/README.md)),
- or put a hash or version in the ConfigMap name, so that every revision gets its own ConfigMap and old pods keep their own,
- or mark the ConfigMap `immutable: true` together with versioned names.

## Clean up

```bash
$ helm uninstall s15-rollback-demo -n s15-rollback --wait
release "s15-rollback-demo" uninstalled

$ kubectl get all,configmap,secret -n s15-rollback
NAME                                        READY   STATUS        RESTARTS   AGE
pod/s15-rollback-demo-web-cf698bdcd-kk4sk   1/1     Terminating   0          4m5s
pod/s15-rollback-demo-web-cf698bdcd-rggz5   1/1     Terminating   0          4m4s

NAME                         DATA   AGE
configmap/kube-root-ca.crt   1      4m58s

$ kubectl delete namespace s15-rollback
namespace "s15-rollback" deleted
```

`helm uninstall` removed the Deployment, Service, ConfigMap and the release Secrets. The two pods shown were in the middle of shutting down. Then I deleted my namespace.
