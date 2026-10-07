# Task 1: Helm Commands

In this part I ran every important Helm command against my own chart and recorded what each one does. I created the chart `webapp` with `helm create`, installed it as the release `s15-web` in my namespace `s15-commands`, and then went through upgrade, history, rollback and uninstall. At the end I added two public chart repositories, searched them and Artifact Hub, and installed one chart from a repository.

All output below is copied from my terminal (colour codes stripped). Long output is cut where you see a `...` line. Some table outputs are piped through `column -t` so that the columns line up in Markdown.

Back to the session overview: [../README.md](../README.md)

## Contents

| # | Command(s) | What it does |
|---|------------|--------------|
| 1 | `helm version` | Shows the Helm client version |
| 2 | `helm create` | Generates a complete starter chart |
| 3 | `helm lint` | Checks a chart for errors and best-practice problems |
| 4 | `helm template` | Renders the templates locally; nothing is sent to the cluster |
| 5 | `helm install --dry-run` | Simulates an install (client side or server side) |
| 6 | `helm install` | Installs a chart as a new release (revision 1) |
| 7 | `helm list` | Lists releases |
| 8 | `helm status` | Shows the state of one release and its resources |
| 9 | `helm get values / manifest / notes / hooks / metadata / all` | Reads what Helm stored for a release |
| 10 | `helm test` | Runs the chart's test hooks against the release |
| 11 | `helm upgrade` | Applies a new chart version or new values (new revision) |
| 12 | `helm history` | Lists all revisions of a release |
| 13 | `helm rollback` | Goes back to an older revision (creates a new revision) |
| 14 | `helm repo add / list / update` | Manages chart repositories |
| 15 | `helm search repo / hub`, `helm show` | Finds charts in added repos and on Artifact Hub |
| 16 | `helm install <repo>/<chart>` | Installs a chart straight from a repository |
| 17 | `helm package`, `helm pull` | Builds a chart archive, downloads a chart archive |
| 18 | `helm uninstall` | Removes a release (optionally keeping its history) |

## Before starting: where the images come from

Docker Hub refused anonymous pulls on this machine while I was working (HTTP 429, the anonymous rate limit). The same official `nginx` and `busybox` images are mirrored on AWS ECR Public under `public.ecr.aws/docker/library/`, so every chart in this session uses that registry:

```bash
$ minikube ssh -- sudo crictl pull docker.io/library/nginx:1.24
E1007 17:48:25.338713    6216 log.go:32] "PullImage from image service failed" err="rpc error: code = Unknown desc = failed to pull and unpack image \"docker.io/library/nginx:1.24\": failed to resolve reference \"docker.io/library/nginx:1.24\": unexpected status from HEAD request to https://registry-1.docker.io/v2/library/nginx/manifests/1.24: 429 Too Many Requests" image="docker.io/library/nginx:1.24"
FATA[0003] pulling image: failed to pull and unpack image "docker.io/library/nginx:1.24": failed to resolve reference "docker.io/library/nginx:1.24": unexpected status from HEAD request to https://registry-1.docker.io/v2/library/nginx/manifests/1.24: 429 Too Many Requests
ssh: Process exited with status 1

$ minikube ssh -- sudo crictl pull public.ecr.aws/docker/library/nginx:1.24
Image is up to date for sha256:9eccb584dbf214f46a885a59f4bbb00dab552b9b10e821e07f2a3cf9c05eae29
```

## 1. helm version

```bash
$ helm version
version.BuildInfo{Version:"v4.3.0", GitCommit:"bec5b06ed841fe5269972d864d5177944fd5970f", GitTreeState:"clean", GoVersion:"go1.27.1", KubeClientVersion:"v1.37"}
```

This machine has Helm **v4.3.0**. The course notes were written for Helm 3. Everything I needed still works, with a few differences that show up later: `--dry-run` now takes a value (`client` or `server`), `--atomic` is deprecated in favour of `--rollback-on-failure`, `helm list --all` was removed, and Helm 4 applies resources with server-side apply by default.

## 2. helm create

```bash
$ helm create webapp
Creating webapp

$ find webapp | sort
webapp
webapp/.helmignore
webapp/Chart.yaml
webapp/charts
webapp/templates
webapp/templates/NOTES.txt
webapp/templates/_helpers.tpl
webapp/templates/deployment.yaml
webapp/templates/hpa.yaml
webapp/templates/httproute.yaml
webapp/templates/ingress.yaml
webapp/templates/service.yaml
webapp/templates/serviceaccount.yaml
webapp/templates/tests
webapp/templates/tests/test-connection.yaml
webapp/values.yaml
```

`helm create` writes a complete, working chart: `Chart.yaml` (metadata), `values.yaml` (defaults), `templates/` (Deployment, Service, ServiceAccount, Ingress, HTTPRoute, HPA, NOTES.txt, `_helpers.tpl` with named templates) and a test hook in `templates/tests/`.

I changed only four things in the generated chart (folder [`webapp/`](webapp/)):

| File | Change | Why |
|------|--------|-----|
| `values.yaml` | `image.repository: public.ecr.aws/docker/library/nginx` | Docker Hub rate limit (see above) |
| `values.yaml` | `resources` set to 50m/64Mi requests, 100m/128Mi limits | The minikube cluster is shared |
| `Chart.yaml` | `appVersion: "1.27-alpine"`, new description | `image.tag` is empty, so the chart uses `appVersion` as the image tag |
| `templates/tests/test-connection.yaml` | test image `public.ecr.aws/docker/library/busybox:1.37` | Same rate-limit reason |

## 3. helm lint

```bash
$ helm lint ./webapp
==> Linting ./webapp
[INFO] Chart.yaml: icon is recommended

1 chart(s) linted, 0 chart(s) failed
```

Lint passes. The only message is an `[INFO]` that a chart icon is recommended, which does not matter for a local chart.

To check that lint really catches mistakes, I copied the chart to a scratch folder and removed one closing brace in `deployment.yaml` (`{{ .Values.replicaCount }` instead of `{{ .Values.replicaCount }}`):

```bash
$ helm lint ./webapp
==> Linting ./webapp
[INFO] Chart.yaml: icon is recommended
[ERROR] templates/: parse error at (webapp/templates/deployment.yaml:9): unexpected "}" in operand

Error: 1 chart(s) linted, 1 chart(s) failed
```

Lint reports the file, the line number and the problem, and exits with an error. That makes it useful as a CI step before anything goes near a cluster.

## 4. helm template

`helm template` renders all templates with the values and prints plain Kubernetes YAML. It does not need a cluster and creates nothing.

```bash
$ helm template s15-web ./webapp --namespace s15-commands
---
# Source: webapp/templates/serviceaccount.yaml
apiVersion: v1
kind: ServiceAccount
metadata:
  name: s15-web-webapp
  labels:
    helm.sh/chart: webapp-0.1.0
    app.kubernetes.io/name: webapp
    app.kubernetes.io/instance: s15-web
    app.kubernetes.io/version: "1.27-alpine"
    app.kubernetes.io/managed-by: Helm
automountServiceAccountToken: true

---
# Source: webapp/templates/service.yaml
apiVersion: v1
kind: Service
metadata:
  name: s15-web-webapp
  labels:
    helm.sh/chart: webapp-0.1.0
    app.kubernetes.io/name: webapp
    app.kubernetes.io/instance: s15-web
    app.kubernetes.io/version: "1.27-alpine"
    app.kubernetes.io/managed-by: Helm
spec:
  type: ClusterIP
  ports:
    - port: 80
      targetPort: http
      protocol: TCP
      name: http
  selector:
    app.kubernetes.io/name: webapp
    app.kubernetes.io/instance: s15-web

---
# Source: webapp/templates/deployment.yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: s15-web-webapp
  labels:
    helm.sh/chart: webapp-0.1.0
    app.kubernetes.io/name: webapp
    app.kubernetes.io/instance: s15-web
    app.kubernetes.io/version: "1.27-alpine"
    app.kubernetes.io/managed-by: Helm
spec:
  replicas: 1
  selector:
    matchLabels:
      app.kubernetes.io/name: webapp
      app.kubernetes.io/instance: s15-web
  template:
    metadata:
      labels:
        helm.sh/chart: webapp-0.1.0
        app.kubernetes.io/name: webapp
        app.kubernetes.io/instance: s15-web
        app.kubernetes.io/version: "1.27-alpine"
        app.kubernetes.io/managed-by: Helm
    spec:
      serviceAccountName: s15-web-webapp
      containers:
        - name: webapp
          image: "public.ecr.aws/docker/library/nginx:1.27-alpine"
          imagePullPolicy: IfNotPresent
          ports:
            - name: http
              containerPort: 80
              protocol: TCP
          livenessProbe:
            httpGet:
              path: /
              port: http
          readinessProbe:
            httpGet:
              path: /
              port: http
          resources:
            limits:
              cpu: 100m
              memory: 128Mi
            requests:
              cpu: 50m
              memory: 64Mi
...
```

Every `{{ ... }}` was replaced: the names come from `.Release.Name` plus the chart name (`s15-web-webapp`), the image tag came from `appVersion` because `image.tag` is empty, and the resources came from my `values.yaml`.

`--show-only` renders a single template, and `--set` overrides a value just for this render:

```bash
$ helm template s15-web ./webapp --namespace s15-commands --show-only templates/service.yaml --set service.port=8080
---
# Source: webapp/templates/service.yaml
apiVersion: v1
kind: Service
metadata:
  name: s15-web-webapp
  labels:
    helm.sh/chart: webapp-0.1.0
    app.kubernetes.io/name: webapp
    app.kubernetes.io/instance: s15-web
    app.kubernetes.io/version: "1.27-alpine"
    app.kubernetes.io/managed-by: Helm
spec:
  type: ClusterIP
  ports:
    - port: 8080
      targetPort: http
      protocol: TCP
      name: http
  selector:
    app.kubernetes.io/name: webapp
    app.kubernetes.io/instance: s15-web
```

The Service port changed to 8080 only in this rendered output. The chart files did not change.

## 5. helm install --dry-run

In Helm 4, `--dry-run` takes a mode. `--dry-run=client` renders everything locally and shows what the release would look like, without talking to the API server:

```bash
$ helm install s15-web ./webapp -n s15-commands --create-namespace --dry-run=client
NAME: s15-web
LAST DEPLOYED: Wed Oct  7 23:19:28 2026
NAMESPACE: s15-commands
STATUS: pending-install
REVISION: 1
DESCRIPTION: Dry run complete
HOOKS:
---
# Source: webapp/templates/tests/test-connection.yaml
apiVersion: v1
kind: Pod
...
MANIFEST:
---
# Source: webapp/templates/serviceaccount.yaml
apiVersion: v1
kind: ServiceAccount
...
        - name: webapp
          image: "public.ecr.aws/docker/library/nginx:1.27-alpine"
          imagePullPolicy: IfNotPresent
...
NOTES:
1. Get the application URL by running these commands:
  export POD_NAME=$(kubectl get pods --namespace s15-commands -l "app.kubernetes.io/name=webapp,app.kubernetes.io/instance=s15-web" -o jsonpath="{.items[0].metadata.name}")
  export CONTAINER_PORT=$(kubectl get pod --namespace s15-commands $POD_NAME -o jsonpath="{.spec.containers[0].ports[0].containerPort}")
  echo "Visit http://127.0.0.1:8080 to use your application"
  kubectl --namespace s15-commands port-forward $POD_NAME 8080:$CONTAINER_PORT

$ kubectl get ns s15-commands
Error from server (NotFound): namespaces "s15-commands" not found

$ helm list -n s15-commands
NAME	NAMESPACE	REVISION	UPDATED	STATUS	CHART	APP VERSION
```

The output has the same parts as a real install (HOOKS, MANIFEST, NOTES) and the status `pending-install` / `Dry run complete`. Nothing was created: the namespace does not exist and `helm list` is empty. `--dry-run=server` also sends the objects to the API server for validation; I used it later for the upgrade (section 11), because it needs the namespace to exist.

## 6. helm install

```bash
$ helm install s15-web ./webapp -n s15-commands --create-namespace --wait --timeout 3m
NAME: s15-web
LAST DEPLOYED: Wed Oct  7 23:19:41 2026
NAMESPACE: s15-commands
STATUS: deployed
REVISION: 1
DESCRIPTION: Install complete
NOTES:
1. Get the application URL by running these commands:
  export POD_NAME=$(kubectl get pods --namespace s15-commands -l "app.kubernetes.io/name=webapp,app.kubernetes.io/instance=s15-web" -o jsonpath="{.items[0].metadata.name}")
  export CONTAINER_PORT=$(kubectl get pod --namespace s15-commands $POD_NAME -o jsonpath="{.spec.containers[0].ports[0].containerPort}")
  echo "Visit http://127.0.0.1:8080 to use your application"
  kubectl --namespace s15-commands port-forward $POD_NAME 8080:$CONTAINER_PORT

$ kubectl get all -n s15-commands
NAME                                  READY   STATUS    RESTARTS   AGE
pod/s15-web-webapp-5d7876d8b9-5wk2k   1/1     Running   0          1s

NAME                     TYPE        CLUSTER-IP      EXTERNAL-IP   PORT(S)   AGE
service/s15-web-webapp   ClusterIP   10.100.26.241   <none>        80/TCP    1s

NAME                             READY   UP-TO-DATE   AVAILABLE   AGE
deployment.apps/s15-web-webapp   1/1     1            1           1s

NAME                                        DESIRED   CURRENT   READY   AGE
replicaset.apps/s15-web-webapp-5d7876d8b9   1         1         1       1s
```

`--create-namespace` created `s15-commands`, and `--wait` made Helm wait until the Deployment was ready before it reported `deployed`. The release is revision 1. The NOTES text at the end is `templates/NOTES.txt` rendered for this release.

## 7. helm list

```bash
$ helm list -n s15-commands | column -t -s $'\t'
NAME     NAMESPACE     REVISION  UPDATED                               STATUS    CHART         APP VERSION
s15-web  s15-commands  1         2026-10-07 23:19:41.327944 +0530 IST  deployed  webapp-0.1.0  1.27-alpine

$ helm list -A --filter '^s15-' | column -t -s $'\t'
NAME     NAMESPACE     REVISION  UPDATED                               STATUS    CHART         APP VERSION
s15-web  s15-commands  1         2026-10-07 23:19:41.327944 +0530 IST  deployed  webapp-0.1.0  1.27-alpine
```

`helm list` only looks at one namespace (the current one, or `-n`). `-A` looks at every namespace, and `--filter` takes a regular expression, so `^s15-` limits the list to my releases on this shared cluster. The `CHART` column is `name-version` from `Chart.yaml` and `APP VERSION` is its `appVersion`.

## 8. helm status

```bash
$ helm status s15-web -n s15-commands
NAME: s15-web
LAST DEPLOYED: Wed Oct  7 23:19:41 2026
NAMESPACE: s15-commands
STATUS: deployed
REVISION: 1
DESCRIPTION: Install complete
RESOURCES:
==> v1/Deployment
NAME             READY   UP-TO-DATE   AVAILABLE   AGE
s15-web-webapp   1/1     1            1           1s

==> v1/Pod(related)
NAME                              READY   STATUS    RESTARTS   AGE
s15-web-webapp-5d7876d8b9-5wk2k   1/1     Running   0          1s

==> v1/ServiceAccount
NAME             AGE
s15-web-webapp   1s

==> v1/Service
NAME             TYPE        CLUSTER-IP      EXTERNAL-IP   PORT(S)   AGE
s15-web-webapp   ClusterIP   10.100.26.241   <none>        80/TCP    1s


NOTES:
1. Get the application URL by running these commands:
  export POD_NAME=$(kubectl get pods --namespace s15-commands -l "app.kubernetes.io/name=webapp,app.kubernetes.io/instance=s15-web" -o jsonpath="{.items[0].metadata.name}")
  export CONTAINER_PORT=$(kubectl get pod --namespace s15-commands $POD_NAME -o jsonpath="{.spec.containers[0].ports[0].containerPort}")
  echo "Visit http://127.0.0.1:8080 to use your application"
  kubectl --namespace s15-commands port-forward $POD_NAME 8080:$CONTAINER_PORT
```

`helm status` shows the release information, the live resources that belong to the release (Deployment, Pod, ServiceAccount, Service) and the NOTES again.

## 9. helm get

`helm get` reads what Helm saved for a release. Helm 3 and 4 save each revision as a Secret in the release namespace (no Tiller):

```bash
$ kubectl get secrets -n s15-commands -l owner=helm
NAME                            TYPE                 DATA   AGE
sh.helm.release.v1.s15-web.v1   helm.sh/release.v1   1      23s
```

### helm get values

```bash
$ helm get values s15-web -n s15-commands
USER-SUPPLIED VALUES:
null

$ helm get values s15-web -n s15-commands --all
COMPUTED VALUES:
affinity: {}
...
image:
  pullPolicy: IfNotPresent
  repository: public.ecr.aws/docker/library/nginx
  tag: ""
...
replicaCount: 1
resources:
  limits:
    cpu: 100m
    memory: 128Mi
  requests:
    cpu: 50m
    memory: 64Mi
securityContext: {}
service:
  port: 80
  type: ClusterIP
...
```

Without flags it prints only the values I passed on the command line. Here that is `null`, because I installed with the chart defaults. `--all` prints the merged result of `values.yaml` plus overrides, which is what the templates actually used.

### helm get manifest

```bash
$ helm get manifest s15-web -n s15-commands
---
# Source: webapp/templates/serviceaccount.yaml
...
---
# Source: webapp/templates/service.yaml
apiVersion: v1
kind: Service
...
---
# Source: webapp/templates/deployment.yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: s15-web-webapp
  labels:
    helm.sh/chart: webapp-0.1.0
    app.kubernetes.io/name: webapp
    app.kubernetes.io/instance: s15-web
    app.kubernetes.io/version: "1.27-alpine"
    app.kubernetes.io/managed-by: Helm
spec:
  replicas: 1
...
```

This is the YAML that Helm sent to Kubernetes for this revision. Test hooks are not part of the manifest.

### helm get notes and helm get hooks

```bash
$ helm get notes s15-web -n s15-commands
NOTES:
1. Get the application URL by running these commands:
  export POD_NAME=$(kubectl get pods --namespace s15-commands -l "app.kubernetes.io/name=webapp,app.kubernetes.io/instance=s15-web" -o jsonpath="{.items[0].metadata.name}")
  export CONTAINER_PORT=$(kubectl get pod --namespace s15-commands $POD_NAME -o jsonpath="{.spec.containers[0].ports[0].containerPort}")
  echo "Visit http://127.0.0.1:8080 to use your application"
  kubectl --namespace s15-commands port-forward $POD_NAME 8080:$CONTAINER_PORT

$ helm get hooks s15-web -n s15-commands
---
# Source: webapp/templates/tests/test-connection.yaml
apiVersion: v1
kind: Pod
metadata:
  name: "s15-web-webapp-test-connection"
  labels:
    helm.sh/chart: webapp-0.1.0
    app.kubernetes.io/name: webapp
    app.kubernetes.io/instance: s15-web
    app.kubernetes.io/version: "1.27-alpine"
    app.kubernetes.io/managed-by: Helm
  annotations:
    "helm.sh/hook": test
spec:
  containers:
    - name: wget
      image: public.ecr.aws/docker/library/busybox:1.37
      command: ['wget']
      args: ['s15-web-webapp:80']
  restartPolicy: Never
```

The test Pod has the `helm.sh/hook: test` annotation, so Helm keeps it apart from the normal manifest and only creates it when `helm test` runs.

### helm get metadata

```bash
$ helm get metadata s15-web -n s15-commands
NAME: s15-web
CHART: webapp
VERSION: 0.1.0
APP_VERSION: 1.27-alpine
ANNOTATIONS:
LABELS: modifiedAt=1791395382,name=s15-web,owner=helm,status=deployed,version=1
DEPENDENCIES:
NAMESPACE: s15-commands
REVISION: 1
STATUS: deployed
DEPLOYED_AT: 2026-10-07T23:19:41+05:30
APPLY_METHOD: server-side apply
```

`APPLY_METHOD: server-side apply` is new in Helm 4. The `LABELS` line shows the labels on the release Secret (`owner=helm`, `status=deployed`, `version=1`).

### helm get all

```bash
$ helm get all s15-web -n s15-commands
NAME: s15-web
LAST DEPLOYED: Wed Oct  7 23:19:41 2026
NAMESPACE: s15-commands
STATUS: deployed
REVISION: 1
CHART: webapp
VERSION: 0.1.0
APP_VERSION: 1.27-alpine
DESCRIPTION: Install complete
USER-SUPPLIED VALUES:
null

COMPUTED VALUES:
affinity: {}
autoscaling:
...
HOOKS:
---
# Source: webapp/templates/tests/test-connection.yaml
...
MANIFEST:
---
# Source: webapp/templates/serviceaccount.yaml
...
NOTES:
1. Get the application URL by running these commands:
  export POD_NAME=$(kubectl get pods --namespace s15-commands -l "app.kubernetes.io/name=webapp,app.kubernetes.io/instance=s15-web" -o jsonpath="{.items[0].metadata.name}")
  export CONTAINER_PORT=$(kubectl get pod --namespace s15-commands $POD_NAME -o jsonpath="{.spec.containers[0].ports[0].containerPort}")
  echo "Visit http://127.0.0.1:8080 to use your application"
  kubectl --namespace s15-commands port-forward $POD_NAME 8080:$CONTAINER_PORT
```

`helm get all` is everything above in one output: release info, user values, computed values, hooks, manifest and notes.

## 10. Checking the app and helm test

I ran a port-forward in the background on my assigned host port 18300 (`kubectl port-forward -n s15-commands svc/s15-web-webapp 18300:80 &`) and used curl:

```bash
$ curl -sI http://localhost:18300/ | head -3
HTTP/1.1 200 OK
Server: nginx/1.27.5
Date: Wed, 07 Oct 2026 17:50:04 GMT

$ curl -s http://localhost:18300/ | grep -i "<h1>"
<h1>Welcome to nginx!</h1>
```

nginx 1.27.5 answered, which matches the image tag `1.27-alpine` that came from `appVersion`.

`helm test` runs the test hook from `templates/tests/` (a busybox Pod that does `wget s15-web-webapp:80`):

```bash
$ helm test s15-web -n s15-commands
NAME: s15-web
LAST DEPLOYED: Wed Oct  7 23:19:41 2026
NAMESPACE: s15-commands
STATUS: deployed
REVISION: 1
DESCRIPTION: Install complete
TEST SUITE:     s15-web-webapp-test-connection
Last Started:   Wed Oct  7 23:20:04 2026
Last Completed: Wed Oct  7 23:20:11 2026
Phase:          Succeeded

$ kubectl get pod s15-web-webapp-test-connection -n s15-commands
NAME                             READY   STATUS      RESTARTS   AGE
s15-web-webapp-test-connection   0/1     Completed   0          7s

$ kubectl logs s15-web-webapp-test-connection -n s15-commands
Connecting to s15-web-webapp:80 (10.100.26.241:80)
saving to 'index.html'
index.html           100% |********************************|   615  0:00:00 ETA
'index.html' saved
```

The test Pod reached the Service from inside the cluster, so the test phase is `Succeeded`.

## 11. helm upgrade

First I checked the upgrade with `--dry-run=server`, which renders the new revision and has the API server validate it, but does not change anything:

```bash
$ helm upgrade s15-web ./webapp -n s15-commands --set replicaCount=2 --set image.tag=1.28-alpine --dry-run=server | grep -E "^(NAME|STATUS|REVISION|DESCRIPTION):|replicas:|image:"
NAME: s15-web
STATUS: pending-upgrade
REVISION: 2
DESCRIPTION: Dry run complete
      image: public.ecr.aws/docker/library/busybox:1.37
  replicas: 2
          image: "public.ecr.aws/docker/library/nginx:1.28-alpine"

$ helm history s15-web -n s15-commands | column -t -s $'\t'
REVISION  UPDATED                   STATUS    CHART         APP VERSION  DESCRIPTION
1         Wed Oct  7 23:19:41 2026  deployed  webapp-0.1.0  1.27-alpine  Install complete
```

The dry run planned revision 2 with 2 replicas and the `1.28-alpine` image, and `helm history` still showed only revision 1. Then the real upgrade:

```bash
$ helm upgrade s15-web ./webapp -n s15-commands --set replicaCount=2 --set image.tag=1.28-alpine --wait --timeout 3m
Release "s15-web" has been upgraded. Happy Helming!
NAME: s15-web
LAST DEPLOYED: Wed Oct  7 23:20:22 2026
NAMESPACE: s15-commands
STATUS: deployed
REVISION: 2
DESCRIPTION: Upgrade complete
NOTES:
1. Get the application URL by running these commands:
  export POD_NAME=$(kubectl get pods --namespace s15-commands -l "app.kubernetes.io/name=webapp,app.kubernetes.io/instance=s15-web" -o jsonpath="{.items[0].metadata.name}")
  export CONTAINER_PORT=$(kubectl get pod --namespace s15-commands $POD_NAME -o jsonpath="{.spec.containers[0].ports[0].containerPort}")
  echo "Visit http://127.0.0.1:8080 to use your application"
  kubectl --namespace s15-commands port-forward $POD_NAME 8080:$CONTAINER_PORT

$ kubectl get deploy,pods -n s15-commands -o wide
NAME                             READY   UP-TO-DATE   AVAILABLE   AGE   CONTAINERS   IMAGES                                            SELECTOR
deployment.apps/s15-web-webapp   2/2     2            2           52s   webapp       public.ecr.aws/docker/library/nginx:1.28-alpine   app.kubernetes.io/instance=s15-web,app.kubernetes.io/name=webapp

NAME                                  READY   STATUS      RESTARTS   AGE   IP            NODE       NOMINATED NODE   READINESS GATES
pod/s15-web-webapp-575b96568-n9bjb    1/1     Running     0          1s    10.244.0.29   minikube   <none>           <none>
pod/s15-web-webapp-575b96568-xp4lm    1/1     Running     0          11s   10.244.0.28   minikube   <none>           <none>
pod/s15-web-webapp-5d7876d8b9-5wk2k   0/1     Completed   0          52s   10.244.0.22   minikube   <none>           <none>
pod/s15-web-webapp-test-connection    0/1     Completed   0          29s   10.244.0.26   minikube   <none>           <none>
```

The Deployment now runs `nginx:1.28-alpine` with 2 replicas. The old pod (`5d7876d8b9-...`) is shown as `Completed` because it was being stopped while I listed the pods.

```bash
$ curl -sI http://localhost:18300/ | grep Server
Server: nginx/1.28.3
```

(After the rollout I restarted the port-forward, because a port-forward to a Service sticks to the one pod it picked when it started.)

## 12. helm history

```bash
$ helm history s15-web -n s15-commands | column -t -s $'\t'
REVISION  UPDATED                   STATUS      CHART         APP VERSION  DESCRIPTION
1         Wed Oct  7 23:19:41 2026  superseded  webapp-0.1.0  1.27-alpine  Install complete
2         Wed Oct  7 23:20:22 2026  deployed    webapp-0.1.0  1.27-alpine  Upgrade complete
```

Each install, upgrade or rollback adds a revision. The current one is `deployed`, older ones are `superseded`. `APP VERSION` stays `1.27-alpine` because it comes from `Chart.yaml`, not from the `image.tag` I overrode.

`helm get values` with `--revision` shows the values of any older revision:

```bash
$ helm get values s15-web -n s15-commands
USER-SUPPLIED VALUES:
image:
  tag: 1.28-alpine
replicaCount: 2

$ helm get values s15-web -n s15-commands --revision 1
USER-SUPPLIED VALUES:
null
```

## 13. helm rollback

```bash
$ helm rollback s15-web 1 -n s15-commands --wait --timeout 3m
Rollback was a success! Happy Helming!

$ helm history s15-web -n s15-commands | column -t -s $'\t'
REVISION  UPDATED                   STATUS      CHART         APP VERSION  DESCRIPTION
1         Wed Oct  7 23:19:41 2026  superseded  webapp-0.1.0  1.27-alpine  Install complete
2         Wed Oct  7 23:20:22 2026  superseded  webapp-0.1.0  1.27-alpine  Upgrade complete
3         Wed Oct  7 23:20:51 2026  deployed    webapp-0.1.0  1.27-alpine  Rollback to 1

$ kubectl get deploy -n s15-commands -o wide
NAME             READY   UP-TO-DATE   AVAILABLE   AGE   CONTAINERS   IMAGES                                            SELECTOR
s15-web-webapp   1/1     1            1           72s   webapp       public.ecr.aws/docker/library/nginx:1.27-alpine   app.kubernetes.io/instance=s15-web,app.kubernetes.io/name=webapp

$ helm get values s15-web -n s15-commands
USER-SUPPLIED VALUES:
null

$ curl -sI http://localhost:18300/ | grep Server
Server: nginx/1.27.5
```

The rollback did not delete revision 2. Helm copied the configuration of revision 1 into a new revision 3 (`Rollback to 1`). The Deployment went back to one replica of `nginx:1.27-alpine`, the user-supplied values are `null` again, and curl shows nginx 1.27.5. Task 2 goes through this in more detail.

## 14. helm repo add / list / update

```bash
$ helm repo list
no repositories to show

$ helm repo add bitnami https://charts.bitnami.com/bitnami
"bitnami" has been added to your repositories

$ helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
"prometheus-community" has been added to your repositories

$ helm repo list
NAME                	URL
bitnami             	https://charts.bitnami.com/bitnami
prometheus-community	https://prometheus-community.github.io/helm-charts

$ helm repo update
Hang tight while we grab the latest from your chart repositories...
...Successfully got an update from the "prometheus-community" chart repository
...Successfully got an update from the "bitnami" chart repository
Update Complete. ⎈Happy Helming!⎈
```

`helm repo add` saves the name and URL in Helm's repository config (`~/Library/Preferences/helm/repositories.yaml` on macOS) and downloads the repository index. `helm repo update` downloads the latest index of every repository, which is like `apt update`.

## 15. helm search repo / hub and helm show

```bash
$ helm search repo nginx
NAME                                          	CHART VERSION	APP VERSION	DESCRIPTION
bitnami/nginx                                 	25.2.1       	1.31.6     	NGINX Open Source is a web server that can be a...
bitnami/nginx-ingress-controller              	12.0.7       	1.13.1     	NGINX Ingress Controller is an Ingress controll...
bitnami/nginx-intel                           	2.1.15       	0.4.9      	DEPRECATED NGINX Open Source for Intel is a lig...
prometheus-community/prometheus-nginx-exporter	1.23.1       	1.5.3      	A Helm chart for NGINX Prometheus Exporter

$ helm search repo bitnami/nginx --versions | head -6
NAME                            	CHART VERSION	APP VERSION	DESCRIPTION
bitnami/nginx                   	25.2.1       	1.31.6     	NGINX Open Source is a web server that can be a...
bitnami/nginx                   	25.2.0       	1.31.6     	NGINX Open Source is a web server that can be a...
bitnami/nginx                   	25.1.15      	1.31.6     	NGINX Open Source is a web server that can be a...
bitnami/nginx                   	25.1.14      	1.31.6     	NGINX Open Source is a web server that can be a...
bitnami/nginx                   	25.1.13      	1.31.6     	NGINX Open Source is a web server that can be a...

$ helm search repo prometheus-community/prometheus-blackbox
NAME                                             	CHART VERSION	APP VERSION	DESCRIPTION
prometheus-community/prometheus-blackbox-exporter	11.20.0      	v0.29.0    	Prometheus Blackbox Exporter

$ helm search hub nginx --max-col-width 60 | head -8
URL                                                         	CHART VERSION  	APP VERSION                                     	DESCRIPTION
https://artifacthub.io/packages/helm/cloudpirates-nginx/n...	0.16.12        	1.31.6                                          	Nginx is a high-performance HTTP server and reverse proxy.
https://artifacthub.io/packages/helm/quench-nginx/nginx     	0.0.15         	1.30.5                                          	High-performance web server, reverse proxy, and load bala...
https://artifacthub.io/packages/helm/krakazyabra/nginx      	1.0.0          	1.19.0                                          	Nginx Helm chart for Kubernetes
https://artifacthub.io/packages/helm/dhinesh/nginx          	25.2.1         	1.31.6                                          	NGINX Open Source is a web server that can be also used a...
https://artifacthub.io/packages/helm/bitnami/nginx          	25.2.1         	1.31.6                                          	NGINX Open Source is a web server that can be also used a...
https://artifacthub.io/packages/helm/niceos/nginx           	1.31.1+niceos.2	1.31.1                                          	Bitnami-compatible NGINX Helm chart for NiceOS
https://artifacthub.io/packages/helm/bitnami-aks/nginx      	13.2.12        	1.23.2                                          	NGINX Open Source is a web server that can be also used a...

$ helm search hub nginx -o json | jq length
304
```

- `helm search repo` searches only the repositories I added (the local index files), so the results come from bitnami and prometheus-community.
- `--versions` lists every chart version, not only the latest.
- `helm search hub` searches Artifact Hub, the public catalogue of charts from many publishers. It does not need `helm repo add`. The JSON output shows 304 results for `nginx`.

`helm show chart` prints a chart's `Chart.yaml` without installing it (`helm show values` prints its default values):

```bash
$ helm show chart prometheus-community/prometheus-blackbox-exporter
apiVersion: v2
appVersion: v0.29.0
description: Prometheus Blackbox Exporter
home: https://github.com/prometheus/blackbox_exporter
keywords:
- prometheus
- blackbox
- monitoring
kubeVersion: '>=1.21.0-0'
maintainers:
...
name: prometheus-blackbox-exporter
sources:
- https://github.com/prometheus/blackbox_exporter
- https://github.com/prometheus-community/helm-charts/tree/main/charts/prometheus-blackbox-exporter
type: application
version: 11.20.0
```

## 16. Installing a chart from a repository

The Bitnami images are on Docker Hub (rate-limited here), so I picked a small chart whose image is on quay.io: the Prometheus Blackbox Exporter. I pinned the chart version and set small resources with `--set`:

```bash
$ helm install s15-blackbox prometheus-community/prometheus-blackbox-exporter -n s15-commands --version 11.20.0 --set resources.requests.cpu=50m --set resources.requests.memory=32Mi --set resources.limits.memory=64Mi --wait --timeout 3m
NAME: s15-blackbox
LAST DEPLOYED: Wed Oct  7 23:21:29 2026
NAMESPACE: s15-commands
STATUS: deployed
REVISION: 1
DESCRIPTION: Install complete
TEST SUITE: None
NOTES:
See https://github.com/prometheus/blackbox_exporter/ for how to configure Prometheus and the Blackbox Exporter.

1. Get the application URL by running these commands:
  export POD_NAME=$(kubectl get pods --namespace s15-commands -l "app.kubernetes.io/name=prometheus-blackbox-exporter,app.kubernetes.io/instance=s15-blackbox" -o jsonpath="{.items[0].metadata.name}")
  export CONTAINER_PORT=$(kubectl get pod --namespace s15-commands $POD_NAME -o jsonpath="{.spec.containers[0].ports[0].containerPort}")
  echo "Visit http://127.0.0.1:8080 to use your application"
  kubectl --namespace s15-commands port-forward $POD_NAME 8080:$CONTAINER_PORT

$ helm list -n s15-commands | column -t -s $'\t'
NAME          NAMESPACE     REVISION  UPDATED                               STATUS    CHART                                 APP VERSION
s15-blackbox  s15-commands  1         2026-10-07 23:21:29.389186 +0530 IST  deployed  prometheus-blackbox-exporter-11.20.0  v0.29.0
s15-web       s15-commands  3         2026-10-07 23:20:51.983987 +0530 IST  deployed  webapp-0.1.0                          1.27-alpine

$ kubectl get pods -n s15-commands -l app.kubernetes.io/instance=s15-blackbox -o wide
NAME                                                         READY   STATUS    RESTARTS   AGE   IP            NODE       NOMINATED NODE   READINESS GATES
s15-blackbox-prometheus-blackbox-exporter-868b69dc58-2jpt8   1/1     Running   0          6s    10.244.0.31   minikube   <none>           <none>
```

The same release workflow works for a chart I did not write. `helm list` now shows both releases. `s15-web` is at revision 3 because of the upgrade and rollback.

## 17. helm package and helm pull

`helm package` builds a versioned `.tgz` from a chart folder, and `helm pull` downloads a chart archive from a repository. I wrote both to my scratch folder (`$PKG`) so that no archives end up in the repo:

```bash
$ helm package ./webapp -d "$PKG" | sed "s#$PKG#\$PKG#"
Successfully packaged chart and saved it to: $PKG/webapp-0.1.0.tgz

$ helm pull prometheus-community/prometheus-blackbox-exporter --version 11.20.0 -d "$PKG"
$ ls "$PKG"
prometheus-blackbox-exporter-11.20.0.tgz
webapp-0.1.0.tgz
```

## 18. helm uninstall

```bash
$ helm uninstall s15-blackbox -n s15-commands
release "s15-blackbox" uninstalled

$ helm uninstall s15-web -n s15-commands --keep-history
release "s15-web" uninstalled

$ helm list -n s15-commands
NAME   	NAMESPACE   	REVISION	UPDATED                             	STATUS     	CHART       	APP VERSION
s15-web	s15-commands	3       	2026-10-07 23:20:51.983987 +0530 IST	uninstalled	webapp-0.1.0	1.27-alpine

$ helm list -n s15-commands --uninstalled | column -t -s $'\t'
NAME     NAMESPACE     REVISION  UPDATED                               STATUS       CHART         APP VERSION
s15-web  s15-commands  3         2026-10-07 23:20:51.983987 +0530 IST  uninstalled  webapp-0.1.0  1.27-alpine

$ helm history s15-web -n s15-commands | column -t -s $'\t'
REVISION  UPDATED                   STATUS       CHART         APP VERSION  DESCRIPTION
1         Wed Oct  7 23:19:41 2026  superseded   webapp-0.1.0  1.27-alpine  Install complete
2         Wed Oct  7 23:20:22 2026  superseded   webapp-0.1.0  1.27-alpine  Upgrade complete
3         Wed Oct  7 23:20:51 2026  uninstalled  webapp-0.1.0  1.27-alpine  Uninstallation complete

$ kubectl get all -n s15-commands
NAME                                                             READY   STATUS      RESTARTS   AGE
pod/s15-blackbox-prometheus-blackbox-exporter-868b69dc58-2jpt8   0/1     Completed   0          29s
pod/s15-web-webapp-5d7876d8b9-n4lwd                              0/1     Completed   0          66s
pod/s15-web-webapp-test-connection                               0/1     Completed   0          114s

$ helm uninstall s15-web -n s15-commands
release "s15-web" uninstalled

$ helm list -n s15-commands --all
Error: unknown flag: --all

$ kubectl get secrets -n s15-commands -l owner=helm
No resources found in s15-commands namespace.

$ helm list -n s15-commands
NAME	NAMESPACE	REVISION	UPDATED	STATUS	CHART	APP VERSION

$ kubectl get all -n s15-commands
NAME                                 READY   STATUS      RESTARTS   AGE
pod/s15-web-webapp-test-connection   0/1     Completed   0          2m5s
```

What I saw:

- `helm uninstall` deletes all resources of the release. With `--keep-history`, Helm also keeps the release records, so the release is still listed with status `uninstalled` (in Helm 4 even a plain `helm list` showed it) and `helm history` still works (revision 3 is now `Uninstallation complete`). A second `helm uninstall` removed the records too, and the `owner=helm` Secrets were gone.
- `helm list --all` from Helm 3 does not exist in Helm 4 (`unknown flag`). The per-status flags such as `--uninstalled` still work.
- The pods listed as `Completed` were being stopped. The test pod `s15-web-webapp-test-connection` stayed, because test hook pods are not part of the release manifest and the chart sets no `helm.sh/hook-delete-policy`. I deleted it and the namespace myself:

```bash
$ kubectl delete pod s15-web-webapp-test-connection -n s15-commands
pod "s15-web-webapp-test-connection" deleted from s15-commands namespace

$ kubectl delete namespace s15-commands
namespace "s15-commands" deleted
```

## Summary of the commands

```text
helm create <chart>                         scaffold a chart
helm lint <chart>                           static checks
helm template <rel> <chart> [-f/--set]      render locally, no cluster
helm install <rel> <chart> --dry-run=client|server
helm install <rel> <chart> -n <ns> --create-namespace --wait
helm list [-n ns | -A] [--filter re] [--uninstalled]
helm status <rel>
helm get values|manifest|notes|hooks|metadata|all <rel> [--revision N] [--all]
helm test <rel>
helm upgrade <rel> <chart> [-f file] [--set k=v] [--reuse-values] [--wait] [--rollback-on-failure]
helm history <rel>
helm rollback <rel> <revision>
helm uninstall <rel> [--keep-history]
helm repo add|list|update|remove
helm search repo|hub <keyword> [--versions]
helm show chart|values|readme|all <repo/chart>
helm package <chart> / helm pull <repo/chart>
```
