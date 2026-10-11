# Session 12: Ingress, ConfigMaps & Secrets

**Name:** Vansh Srivastava
**Enrollment No.:** 24bcs10567
**Session:** 12

This session is about getting configuration and credentials out of container images (ConfigMaps and Secrets) and exposing several services behind one HTTP entry point (Ingress). I built a small "Yatri" booking app from the course's `04-full-demo` (an nginx frontend and a Python backend that reads a ConfigMap and a Secret), put it behind ingress-nginx with path-based and host-based rules, looked at how the controller turns an Ingress into nginx config, and debugged two real problems: the trailing-newline Secret bug from the course post-mortem, and a rewrite rule in the course Ingress that sent every frontend URL to `/`.

Course material comes from https://github.com/Nency-Ravaliya/devops-heros (folder `session-12-ingress-configmaps-secrets`). Where I copied a course file, the file header says so and lists my changes.

## Folder structure

```text
session-12-ingress-configmaps-secrets/
├── README.md
├── .gitignore
├── 00-namespace.yaml                  # namespace s12-demo
├── 01-configmap/
│   ├── app-config.yaml                # ConfigMaps yatri-app-config (env keys) + yatri-app-files (file keys)
│   └── configmap-demo-pod.yaml        # Pod using envFrom, env.valueFrom and a ConfigMap volume
├── 02-secret/
│   ├── db-secret.demo.yaml            # demo Secret, obviously fake values (safe to commit)
│   ├── db-secret.template.yaml        # template only, placeholders, never applied
│   └── secret-demo-pod.yaml           # Pod using secretKeyRef env vars and a Secret volume
├── 03-ingress/
│   ├── frontend.yaml                  # course 04-full-demo frontend (nginx) + ClusterIP Service
│   ├── backend.yaml                   # course 04-full-demo backend (Python) + ClusterIP Service
│   ├── ingress-path-based.yaml        # yatri.s12.local: /api -> backend, / -> frontend
│   └── ingress-host-based.yaml        # web.s12.local -> frontend, api.s12.local -> backend
├── 04-ingress-vs-controller/
│   ├── README.md                      # Task 4: Ingress vs Ingress Controller
│   └── ingress-no-controller.yaml     # Ingress with an IngressClass nobody implements
├── 05-troubleshooting/
│   ├── course-troubleshooting/
│   │   └── secret-base64-gotcha.md    # copied from the course troubleshooting/ folder
│   ├── 01-newline-secret/             # reproduction of the post-mortem with a real Postgres
│   │   ├── namespace.yaml, postgres.yaml, app.yaml
│   │   ├── app-secret-broken.yaml     # password encoded with plain echo (has \n)
│   │   └── app-secret-fixed.yaml      # password encoded with echo -n
│   └── 02-rewrite-target/
│       └── ingress-course-original.yaml   # course 04-full-demo/ingress.yaml (only name/ns/host changed)
└── screenshots/                       # headless Chrome captures through the Ingress
```

## Environment

- macOS on Apple Silicon (arm64), Docker via Colima, minikube v1.39.0 with Kubernetes v1.37.0 (containerd), one shared node.
- Ingress controller: the minikube `ingress` addon (ingress-nginx v1.15.1, IngressClass `nginx`). The node IP is not reachable from my Mac, so I port-forwarded the controller Service to `localhost:18280` and sent requests with a `Host` header (or `curl --resolve`).
- My objects live in the namespaces `s12-demo` and `s12-troubleshoot`; hostnames end in `.s12.local` so they cannot clash with other users of the same cluster.
- Images: Docker Hub refused anonymous pulls from this network, so every image in my manifests points to the AWS ECR Public mirror of the same official image (`public.ecr.aws/docker/library/<name>:<tag>`). This is the error I got the first time, with `busybox:1.36` from Docker Hub:

```bash
$ kubectl -n s12-demo get pod secret-demo; kubectl -n s12-demo describe pod secret-demo | sed -n '/^Events/,$p'
NAME          READY   STATUS             RESTARTS   AGE
secret-demo   0/1     ImagePullBackOff   0          92s
Events:
  Type     Reason     Age                From               Message
  ----     ------     ----               ----               -------
  Normal   Scheduled  92s                default-scheduler  Successfully assigned s12-demo/secret-demo to minikube
  Normal   Pulling    51s (x3 over 92s)  kubelet            spec.containers{app}: Pulling image "busybox:1.36"
  Warning  Failed     48s (x3 over 89s)  kubelet            spec.containers{app}: Failed to pull image "busybox:1.36": failed to pull and unpack image "docker.io/library/busybox:1.36": failed to resolve reference "docker.io/library/busybox:1.36": unexpected status from HEAD request to https://registry-1.docker.io/v2/library/busybox/manifests/1.36: 429 Too Many Requests
  Warning  Failed     48s (x3 over 89s)  kubelet            spec.containers{app}: Error: ErrImagePull
  Normal   BackOff    9s (x5 over 89s)   kubelet            spec.containers{app}: Back-off pulling image "busybox:1.36"
  Warning  Failed     9s (x5 over 89s)   kubelet            spec.containers{app}: Error: ImagePullBackOff
```

The image was already in the node's cache. The kubelet still pulled it again because Kubernetes 1.37 checks pull credentials per image name (`KubeletEnsureSecretPulledImages`). Another user had pulled the same image ID under the `public.ecr.aws/...` name, so for the `docker.io/...` name the kubelet asked Docker Hub again and got the 429. Switching my manifests to the mirror name fixed it.

## Task 1: ConfigMap

A ConfigMap holds non-secret settings outside the image. [01-configmap/app-config.yaml](01-configmap/app-config.yaml) has two ConfigMaps:

- `yatri-app-config`: the five `KEY=VALUE` settings from the course demo (`ENVIRONMENT`, `LOG_LEVEL`, `APP_PORT`, `DEFAULT_CURRENCY`, `MAX_BOOKING_DAYS`), used as environment variables.
- `yatri-app-files`: file-style keys (`theme.txt`, `app.properties`), used as a volume. I kept them separate because `envFrom` would otherwise also try to turn `theme.txt` into an environment variable.

[01-configmap/configmap-demo-pod.yaml](01-configmap/configmap-demo-pod.yaml) uses the ConfigMaps in three ways: `envFrom` (all keys), `env.valueFrom.configMapKeyRef` (one key under a new name, `LOG_LEVEL` -> `APP_LOG_LEVEL`), and a `configMap` volume mounted at `/etc/config`. That also covers the course homework (theme colour mounted as `/etc/config/theme.txt` in an nginx container).

Create and inspect:

```bash
$ kubectl apply -f 00-namespace.yaml
namespace/s12-demo created
$ kubectl apply -f 01-configmap/app-config.yaml
configmap/yatri-app-config created
configmap/yatri-app-files created
$ kubectl -n s12-demo get configmaps
NAME               DATA   AGE
kube-root-ca.crt   1      1s
yatri-app-config   5      0s
yatri-app-files    2      0s
$ kubectl -n s12-demo describe configmap yatri-app-files
Name:         yatri-app-files
Namespace:    s12-demo
Labels:       app=yatri-app
Annotations:  <none>

Data
====
app.properties:
----
feature.dark_mode=true
cache.ttl_seconds=300
booking.max_passengers=6


theme.txt:
----
theme_color=teal



BinaryData
====

Events:  <none>
$ kubectl -n s12-demo get configmap yatri-app-config -o jsonpath='{.data.ENVIRONMENT}'; echo
production
```

Inject into a Pod and check from inside the container:

```bash
$ kubectl apply -f 01-configmap/configmap-demo-pod.yaml
pod/configmap-demo created
$ kubectl -n s12-demo wait --for=condition=Ready pod/configmap-demo --timeout=90s
pod/configmap-demo condition met
$ kubectl -n s12-demo get pod configmap-demo -o wide
NAME             READY   STATUS    RESTARTS   AGE   IP             NODE       NOMINATED NODE   READINESS GATES
configmap-demo   1/1     Running   0          0s    10.244.0.107   minikube   <none>           <none>
$ kubectl -n s12-demo exec configmap-demo -- sh -c "env | sort | grep -E \"^(ENVIRONMENT|LOG_LEVEL|APP_LOG_LEVEL|APP_PORT|DEFAULT_CURRENCY|MAX_BOOKING_DAYS)=\""
APP_LOG_LEVEL=INFO
APP_PORT=5000
DEFAULT_CURRENCY=INR
ENVIRONMENT=production
LOG_LEVEL=INFO
MAX_BOOKING_DAYS=30
$ kubectl -n s12-demo exec configmap-demo -- ls -la /etc/config
total 16
drwxrwxrwx    3 root     root          4096 Oct  7 18:00 .
drwxr-xr-x    1 root     root          4096 Oct  7 18:00 ..
drwxr-xr-x    2 root     root          4096 Oct  7 18:00 ..2026_10_07_18_00_19.3425863039
lrwxrwxrwx    1 root     root            32 Oct  7 18:00 ..data -> ..2026_10_07_18_00_19.3425863039
lrwxrwxrwx    1 root     root            21 Oct  7 18:00 app.properties -> ..data/app.properties
lrwxrwxrwx    1 root     root            16 Oct  7 18:00 theme.txt -> ..data/theme.txt
$ kubectl -n s12-demo exec configmap-demo -- cat /etc/config/theme.txt /etc/config/app.properties
theme_color=teal
feature.dark_mode=true
cache.ttl_seconds=300
booking.max_passengers=6
```

All five keys arrived as environment variables, the renamed key `APP_LOG_LEVEL` too, and each file key became a file. The files are symlinks into a timestamped `..data` directory. The kubelet uses that to swap in a new version of the ConfigMap in one step.

**What happens when the ConfigMap changes.** I changed one env key and one file key, then read both from the running Pod (the container clock is UTC):

```bash
$ kubectl -n s12-demo patch configmap yatri-app-config --type merge -p '{"data":{"LOG_LEVEL":"DEBUG"}}'
configmap/yatri-app-config patched
$ kubectl -n s12-demo patch configmap yatri-app-files --type merge -p '{"data":{"theme.txt":"theme_color=orange\n"}}'
configmap/yatri-app-files patched
$ kubectl -n s12-demo exec configmap-demo -- sh -c "date -u +%H:%M:%S; env | grep ^LOG_LEVEL=; cat /etc/config/theme.txt"
18:01:12
LOG_LEVEL=INFO
theme_color=teal
$ kubectl -n s12-demo exec configmap-demo -- sh -c "date -u +%H:%M:%S; env | grep ^LOG_LEVEL=; cat /etc/config/theme.txt"
18:01:31
LOG_LEVEL=INFO
theme_color=orange
$ kubectl -n s12-demo delete pod configmap-demo && kubectl apply -f 01-configmap/configmap-demo-pod.yaml
pod "configmap-demo" deleted from s12-demo namespace
pod/configmap-demo created
$ kubectl -n s12-demo wait --for=condition=Ready pod/configmap-demo --timeout=90s
pod/configmap-demo condition met
$ kubectl -n s12-demo exec configmap-demo -- sh -c "env | grep ^LOG_LEVEL=; cat /etc/config/theme.txt"
LOG_LEVEL=DEBUG
theme_color=orange
$ kubectl apply -f 01-configmap/app-config.yaml
configmap/yatri-app-config configured
configmap/yatri-app-files configured
```

The mounted file changed by itself about 20 seconds later; in an earlier try it took about 80 seconds, because it depends on the kubelet sync period. The environment variable did not change. Environment variables are set once when the container starts, so the new `LOG_LEVEL` only appeared after I recreated the Pod. For a Deployment, `kubectl rollout restart` does the same thing. At the end I re-applied the original file to put the values back.

## Task 2: Secret

A Secret is meant for sensitive values. It is used the same way as a ConfigMap (env or volume), but the values are stored base64-encoded, `kubectl describe` hides them, and access can be limited separately with RBAC.

Files:

- [02-secret/db-secret.demo.yaml](02-secret/db-secret.demo.yaml): a demo Secret with obviously fake values (`demo_user` / `demo-password-123`). It is the only Secret manifest with values in the repo.
- [02-secret/db-secret.template.yaml](02-secret/db-secret.template.yaml): the shape of the real Secret with placeholders. It is never applied.
- [02-secret/secret-demo-pod.yaml](02-secret/secret-demo-pod.yaml): Pod reading two keys as env vars (`secretKeyRef`) and mounting the whole Secret at `/etc/db-credentials` (mode `0400`).

**Base64 is encoding, not encryption.** Anyone who can read the Secret object gets the value back in one command:

```bash
$ kubectl apply -f 02-secret/db-secret.demo.yaml
secret/yatri-db-secret-demo created
$ kubectl -n s12-demo get secret yatri-db-secret-demo
NAME                   TYPE     DATA   AGE
yatri-db-secret-demo   Opaque   3      0s
$ kubectl -n s12-demo describe secret yatri-db-secret-demo
Name:         yatri-db-secret-demo
Namespace:    s12-demo
Labels:       app=yatri-app
Annotations:  <none>

Type:  Opaque

Data
====
POSTGRES_DB:        7 bytes
POSTGRES_PASSWORD:  17 bytes
POSTGRES_USER:      9 bytes
$ kubectl -n s12-demo get secret yatri-db-secret-demo -o yaml | grep -A4 "^data:"
data:
  POSTGRES_DB: ZGVtb19kYg==
  POSTGRES_PASSWORD: ZGVtby1wYXNzd29yZC0xMjM=
  POSTGRES_USER: ZGVtb191c2Vy
kind: Secret
$ kubectl -n s12-demo get secret yatri-db-secret-demo -o jsonpath='{.data.POSTGRES_PASSWORD}' | base64 --decode; echo
demo-password-123
$ echo -n "demo-password-123" | base64
ZGVtby1wYXNzd29yZC0xMjM=
```

`describe` only shows byte counts. `-o yaml` plus `base64 --decode` gives back the plain password, and anyone can produce the same string with `base64`.

**Creating the real Secret without writing it to a file.** The Secret the app uses (`yatri-db-secret`) is created directly in the cluster. The password comes from a shell variable (here a random one from `openssl`), so it is never in a file, in Git or in my shell history:

```bash
$ DB_PASSWORD="$(openssl rand -base64 18)"
kubectl -n s12-demo create secret generic yatri-db-secret \
  --from-literal=POSTGRES_USER=yatri_admin \
  --from-literal=POSTGRES_PASSWORD="$DB_PASSWORD" \
  --from-literal=POSTGRES_DB=yatri_production_db
unset DB_PASSWORD
secret/yatri-db-secret created
$ kubectl -n s12-demo describe secret yatri-db-secret | sed -n "/^Type/,\$p"
Type:  Opaque

Data
====
POSTGRES_DB:        19 bytes
POSTGRES_PASSWORD:  24 bytes
POSTGRES_USER:      11 bytes
```

This is what a generated Secret manifest looks like (fake value). If someone committed this file, the "secret" would be readable by everyone who can read the repo:

```bash
$ kubectl -n s12-demo create secret generic example-secret --from-literal=API_KEY=demo-api-key-123 --dry-run=client -o yaml
apiVersion: v1
data:
  API_KEY: ZGVtby1hcGkta2V5LTEyMw==
kind: Secret
metadata:
  name: example-secret
  namespace: s12-demo
```

**Inject into a Pod and check from inside the container.** I print the password length and compare the env value with the file value instead of printing the password:

```bash
$ kubectl apply -f 02-secret/secret-demo-pod.yaml
pod/secret-demo created
$ kubectl -n s12-demo wait --for=condition=Ready pod/secret-demo --timeout=90s
pod/secret-demo condition met
$ kubectl -n s12-demo get pod secret-demo
NAME          READY   STATUS    RESTARTS   AGE
secret-demo   1/1     Running   0          1s
$ kubectl -n s12-demo exec secret-demo -- sh -c 'echo "DB_USER=$DB_USER"; echo "DB_PASSWORD length: ${#DB_PASSWORD}"'
DB_USER=yatri_admin
DB_PASSWORD length: 24
$ kubectl -n s12-demo exec secret-demo -- ls -lL /etc/db-credentials
total 12
-r--------    1 root     root            19 Oct  7 18:00 POSTGRES_DB
-r--------    1 root     root            24 Oct  7 18:00 POSTGRES_PASSWORD
-r--------    1 root     root            11 Oct  7 18:00 POSTGRES_USER
$ kubectl -n s12-demo exec secret-demo -- sh -c "cat /etc/db-credentials/POSTGRES_USER; echo; cat /etc/db-credentials/POSTGRES_DB; echo"
yatri_admin
yatri_production_db
$ kubectl -n s12-demo exec secret-demo -- sh -c '[ "$DB_PASSWORD" = "$(cat /etc/db-credentials/POSTGRES_PASSWORD)" ] && echo "env value == file value"'
env value == file value
$ kubectl -n s12-demo exec secret-demo -- sh -c "mount | grep db-credentials"
tmpfs on /etc/db-credentials type tmpfs (ro,relatime,size=32768k,inode64,noswap)
```

The Secret volume is a read-only `tmpfs` (in memory, never written to the node's disk), and `defaultMode: 0400` makes the files readable only by the owner.

**Why Secrets must not be committed to Git**

- A Secret manifest only base64-encodes the values. Anyone with read access to the repo (or a fork, a clone, a CI log) can decode them, as shown above.
- Git keeps history. Deleting the file later does not remove the value from older commits, so a leaked credential has to be rotated, not just removed.
- Public repos are scanned by bots within minutes of a push.
- Inside the cluster the protection comes from RBAC on `get secret`, and in production from encryption at rest for etcd (KMS). Neither of these protects a file in Git.

What I would use instead:

| Option | How it works |
| :--- | :--- |
| Sealed Secrets (Bitnami) | `kubeseal` encrypts the Secret with the controller's public key. Only the encrypted `SealedSecret` is committed, and only the controller in the cluster can decrypt it. |
| External Secrets Operator | The real value stays in AWS Secrets Manager / Vault / GCP Secret Manager. Git only contains an `ExternalSecret` that says which key to fetch, and the operator creates the Kubernetes Secret. |
| SOPS (with age or KMS) | Encrypts only the values inside the YAML, so the file can be committed and diffed. Decryption happens at deploy time (for example with Argo CD or Flux plugins). |
| `kubectl create secret --from-literal` / `--from-file` | What I did here: create the Secret straight from a variable or a local untracked file. Fine for a lab, but hard to repeat in a team. |

My `.gitignore` also ignores `*.env`, `*.key`, `*.pem` and `*secret*.local.yaml`, so local credential files cannot be added by accident.

## Task 3: Ingress

**Deploy the app and Services.** [03-ingress/frontend.yaml](03-ingress/frontend.yaml) and [03-ingress/backend.yaml](03-ingress/backend.yaml) are the course `04-full-demo` files. The backend reads `yatri-app-config` (Task 1) and the Secret `yatri-db-secret` (Task 2). I added two lines to its response: `SERVED_BY` (pod hostname) and `REQUEST_PATH` (the path the pod actually received). Both Services are `ClusterIP`, so they are not reachable from outside the cluster without the Ingress.

```bash
$ kubectl apply -f 03-ingress/frontend.yaml -f 03-ingress/backend.yaml
deployment.apps/yatri-frontend created
service/yatri-frontend-service created
deployment.apps/yatri-backend created
service/yatri-backend-service created
$ kubectl -n s12-demo rollout status deploy/yatri-frontend --timeout=120s && kubectl -n s12-demo rollout status deploy/yatri-backend --timeout=120s
Waiting for deployment "yatri-frontend" rollout to finish: 0 of 2 updated replicas are available...
Waiting for deployment "yatri-frontend" rollout to finish: 1 of 2 updated replicas are available...
deployment "yatri-frontend" successfully rolled out
Waiting for deployment "yatri-backend" rollout to finish: 0 of 2 updated replicas are available...
Waiting for deployment "yatri-backend" rollout to finish: 1 of 2 updated replicas are available...
deployment "yatri-backend" successfully rolled out
$ kubectl -n s12-demo get deploy,pods,svc,endpointslices -l "app in (yatri-frontend,yatri-backend)" -o wide
NAME                             READY   UP-TO-DATE   AVAILABLE   AGE   CONTAINERS   IMAGES                                                 SELECTOR
deployment.apps/yatri-backend    2/2     2            2           6s    backend      public.ecr.aws/docker/library/python:3.11-alpine3.19   app=yatri-backend
deployment.apps/yatri-frontend   2/2     2            2           6s    frontend     public.ecr.aws/docker/library/nginx:1.25-alpine        app=yatri-frontend

NAME                                  READY   STATUS    RESTARTS   AGE   IP             NODE       NOMINATED NODE   READINESS GATES
pod/yatri-backend-6f77664494-r6w89    1/1     Running   0          6s    10.244.0.129   minikube   <none>           <none>
pod/yatri-backend-6f77664494-t6qk6    1/1     Running   0          6s    10.244.0.128   minikube   <none>           <none>
pod/yatri-frontend-6bfb478759-6h764   1/1     Running   0          6s    10.244.0.127   minikube   <none>           <none>
pod/yatri-frontend-6bfb478759-9frb8   1/1     Running   0          6s    10.244.0.126   minikube   <none>           <none>

NAME                             TYPE        CLUSTER-IP     EXTERNAL-IP   PORT(S)   AGE   SELECTOR
service/yatri-backend-service    ClusterIP   10.100.170.8   <none>        80/TCP    6s    app=yatri-backend
service/yatri-frontend-service   ClusterIP   10.97.63.206   <none>        80/TCP    6s    app=yatri-frontend

NAME                                                          ADDRESSTYPE   PORTS   ENDPOINTS                   AGE
endpointslice.discovery.k8s.io/yatri-backend-service-z98fg    IPv4          5000    10.244.0.129,10.244.0.128   6s
endpointslice.discovery.k8s.io/yatri-frontend-service-ld2pn   IPv4          80      10.244.0.126,10.244.0.127   6s
```

To reach the controller from my Mac I port-forwarded its Service:

```bash
$ kubectl -n ingress-nginx port-forward svc/ingress-nginx-controller 18280:80 &   # left running in the background
Forwarding from 127.0.0.1:18280 -> 80
Forwarding from [::1]:18280 -> 80
```

**Path-based routing.** [03-ingress/ingress-path-based.yaml](03-ingress/ingress-path-based.yaml) is the course Ingress for one host (`yatri.s12.local`) with two paths. `/api(/|$)(.*)` goes to the backend, and `rewrite-target: /$2` strips the `/api` prefix. Everything else goes to the frontend. (I changed the frontend path from `/` to `/()(.*)`, see Task 5 issue 2.)

```bash
$ kubectl apply -f 03-ingress/ingress-path-based.yaml
ingress.networking.k8s.io/yatri-ingress created
$ kubectl -n s12-demo get ingress yatri-ingress
NAME            CLASS   HOSTS             ADDRESS        PORTS   AGE
yatri-ingress   nginx   yatri.s12.local   192.168.49.2   80      13s
$ kubectl -n s12-demo describe ingress yatri-ingress
Name:             yatri-ingress
Labels:           app=yatri-app
Namespace:        s12-demo
Address:          192.168.49.2
Ingress Class:    nginx
Default backend:  <default>
Rules:
  Host             Path  Backends
  ----             ----  --------
  yatri.s12.local  
                   /api(/|$)(.*)   yatri-backend-service:80 (10.244.0.129:5000,10.244.0.128:5000)
                   /()(.*)         yatri-frontend-service:80 (10.244.0.126:80,10.244.0.127:80)
Annotations:       nginx.ingress.kubernetes.io/rewrite-target: /$2
                   nginx.ingress.kubernetes.io/ssl-redirect: false
                   nginx.ingress.kubernetes.io/use-regex: true
Events:
  Type    Reason  Age               From                      Message
  ----    ------  ----              ----                      -------
  Normal  Sync    1s (x2 over 13s)  nginx-ingress-controller  Scheduled for sync
```

The `ADDRESS` (the node IP) is filled in by the controller once it has picked up the Ingress. `describe` also lists the pod IPs behind each Service.

Test the routing:

```bash
$ curl -s -H "Host: yatri.s12.local" http://localhost:18280/ | grep -i "<title>"
<title>Welcome to nginx!</title>
$ curl -s -H "Host: yatri.s12.local" http://localhost:18280/api/
Yatri Backend API
=================
ENVIRONMENT     : production
LOG_LEVEL       : INFO
DEFAULT_CURRENCY: INR
POSTGRES_USER   : yatri_admin
POSTGRES_DB     : yatri_production_db
SERVED_BY       : yatri-backend-6f77664494-r6w89
REQUEST_PATH    : /
$ curl -s -H "Host: yatri.s12.local" http://localhost:18280/api/bookings/42
Yatri Backend API
=================
ENVIRONMENT     : production
LOG_LEVEL       : INFO
DEFAULT_CURRENCY: INR
POSTGRES_USER   : yatri_admin
POSTGRES_DB     : yatri_production_db
SERVED_BY       : yatri-backend-6f77664494-r6w89
REQUEST_PATH    : /bookings/42
$ for i in 1 2 3 4; do curl -s -H "Host: yatri.s12.local" http://localhost:18280/api/ | grep SERVED_BY; done
SERVED_BY       : yatri-backend-6f77664494-t6qk6
SERVED_BY       : yatri-backend-6f77664494-r6w89
SERVED_BY       : yatri-backend-6f77664494-t6qk6
SERVED_BY       : yatri-backend-6f77664494-t6qk6
$ curl -s -o /dev/null -w "%{http_code}\n" -H "Host: unknown.s12.local" http://localhost:18280/
404
```

What this shows:

- `/` reached the nginx frontend and `/api/...` reached the Python backend, through one entry point.
- `/api/bookings/42` arrived at the pod as `/bookings/42`, so the rewrite works.
- The backend values come from the ConfigMap (`ENVIRONMENT`, `LOG_LEVEL`, `DEFAULT_CURRENCY`) and the Secret (`POSTGRES_USER`, `POSTGRES_DB`). The password is not printed.
- Requests were spread over both backend replicas.
- A host with no rule got the controller's default 404.

**Host-based routing.** [03-ingress/ingress-host-based.yaml](03-ingress/ingress-host-based.yaml) sends `web.s12.local` to the frontend and `api.s12.local` to the backend, with no rewrite:

```bash
$ kubectl apply -f 03-ingress/ingress-host-based.yaml
ingress.networking.k8s.io/yatri-host-ingress created
$ kubectl -n s12-demo get ingress
NAME                 CLASS   HOSTS                         ADDRESS        PORTS   AGE
yatri-host-ingress   nginx   web.s12.local,api.s12.local   192.168.49.2   80      46s
yatri-ingress        nginx   yatri.s12.local               192.168.49.2   80      74s
$ kubectl -n s12-demo describe ingress yatri-host-ingress | sed -n "/^Rules/,/^Annotations/p"
Rules:
  Host           Path  Backends
  ----           ----  --------
  web.s12.local  
                 /   yatri-frontend-service:80 (10.244.0.126:80,10.244.0.127:80)
  api.s12.local  
                 /   yatri-backend-service:80 (10.244.0.129:5000,10.244.0.128:5000)
Annotations:     nginx.ingress.kubernetes.io/ssl-redirect: false
$ curl -s --resolve web.s12.local:18280:127.0.0.1 http://web.s12.local:18280/ | grep -i "<title>"
<title>Welcome to nginx!</title>
$ curl -s --resolve api.s12.local:18280:127.0.0.1 http://api.s12.local:18280/bookings/42
Yatri Backend API
=================
ENVIRONMENT     : production
LOG_LEVEL       : INFO
DEFAULT_CURRENCY: INR
POSTGRES_USER   : yatri_admin
POSTGRES_DB     : yatri_production_db
SERVED_BY       : yatri-backend-6f77664494-t6qk6
REQUEST_PATH    : /bookings/42
$ for h in web.s12.local api.s12.local yatri.s12.local nothing.s12.local; do curl -s -o /dev/null -w "$h/ -> HTTP %{http_code}, %{content_type}\n" -H "Host: $h" http://localhost:18280/; done
web.s12.local/ -> HTTP 200, text/html
api.s12.local/ -> HTTP 200, text/plain
yatri.s12.local/ -> HTTP 200, text/html
nothing.s12.local/ -> HTTP 404, text/html
```

The same port, the same path `/`, and a different `Host` header gave a different backend (HTML from nginx, plain text from Python). `curl --resolve` sends the real host name, the way a browser would after a DNS lookup.

Screenshots taken with headless Chrome through the same port-forward (Chrome was told to resolve `*.s12.local` to 127.0.0.1):

![yatri.s12.local/ served by the nginx frontend through the Ingress](screenshots/01-path-based-frontend.png)

![yatri.s12.local/api/bookings/42 routed to the backend, prefix stripped](screenshots/02-path-based-api.png)

![api.s12.local/bookings/42 routed to the backend by host name](screenshots/03-host-based-api.png)

Everything the app uses, in one namespace:

```bash
$ kubectl -n s12-demo get configmap,secret,deploy,svc,ingress
NAME                         DATA   AGE
configmap/kube-root-ca.crt   1      18m
configmap/yatri-app-config   5      18m
configmap/yatri-app-files    2      18m

NAME                          TYPE     DATA   AGE
secret/yatri-db-secret        Opaque   3      15m
secret/yatri-db-secret-demo   Opaque   3      16m

NAME                             READY   UP-TO-DATE   AVAILABLE   AGE
deployment.apps/yatri-backend    2/2     2            2           8m39s
deployment.apps/yatri-frontend   2/2     2            2           8m39s

NAME                             TYPE        CLUSTER-IP     EXTERNAL-IP   PORT(S)   AGE
service/yatri-backend-service    ClusterIP   10.100.170.8   <none>        80/TCP    8m39s
service/yatri-frontend-service   ClusterIP   10.97.63.206   <none>        80/TCP    8m39s

NAME                                           CLASS   HOSTS                         ADDRESS        PORTS   AGE
ingress.networking.k8s.io/yatri-host-ingress   nginx   web.s12.local,api.s12.local   192.168.49.2   80      7m56s
ingress.networking.k8s.io/yatri-ingress        nginx   yatri.s12.local               192.168.49.2   80      8m24s
```

## Task 4: Ingress vs Ingress Controller

The full write-up with the real controller pod, the IngressClass, the nginx config the controller generated from my Ingress, and an experiment with an Ingress that no controller owns is in [04-ingress-vs-controller/README.md](04-ingress-vs-controller/README.md). Summary:

| | Ingress | Ingress Controller |
| :--- | :--- | :--- |
| What it is | An API object (`networking.k8s.io/v1`), just data in etcd | A program running in pods (here `ingress-nginx-controller` in namespace `ingress-nginx`) |
| What it contains | Hosts, paths, backend Services, TLS secret names, annotations | A reverse proxy (nginx) plus a loop that watches Ingress, Service and EndpointSlice objects |
| Does it handle traffic? | No | Yes, every request goes through it |
| Who creates it | The app team, one per app | The cluster admin, once per cluster (here the minikube addon) |
| Link between them | `spec.ingressClassName: nginx` | the IngressClass `nginx` with `controller: k8s.io/ingress-nginx` |

Both are needed: the Ingress says what should happen and the controller does it. An Ingress that names a class no controller owns is stored but has no effect (no ADDRESS, 404 for its host). A controller without any Ingress objects only returns its default 404.

## Task 5: Troubleshooting

I copied the course `troubleshooting/` folder to [05-troubleshooting/course-troubleshooting/](05-troubleshooting/course-troubleshooting/secret-base64-gotcha.md). It is a post-mortem about a database login that fails because the password in a Secret was base64-encoded with plain `echo`. I rebuilt that incident with a real Postgres (issue 1). While testing the course Ingress I also found a second, real problem (issue 2).

### Issue 1: the trailing-newline Secret (course post-mortem)

**Setup.** [postgres.yaml](05-troubleshooting/01-newline-secret/postgres.yaml) runs Postgres 16 with user `yatri_admin` / password `secretpassword` (the course's fake demo password). [app.yaml](05-troubleshooting/01-newline-secret/app.yaml) is a small "yatri-api" that logs in with `psql` using the Secret `yatri-db-secret` and exits 1 if the login fails. [app-secret-broken.yaml](05-troubleshooting/01-newline-secret/app-secret-broken.yaml) has the password encoded the wrong way, with `echo "secretpassword" | base64`.

```bash
$ kubectl apply -f namespace.yaml -f postgres.yaml
namespace/s12-troubleshoot created
secret/postgres-server-secret created
deployment.apps/postgres created
service/postgres created
$ kubectl -n s12-troubleshoot rollout status deploy/postgres --timeout=180s
Waiting for deployment "postgres" rollout to finish: 0 of 1 updated replicas are available...
deployment "postgres" successfully rolled out
$ kubectl apply -f app-secret-broken.yaml -f app.yaml
secret/yatri-db-secret created
deployment.apps/yatri-api created
```

**1. Identify the problem.**

```bash
$ kubectl -n s12-troubleshoot get pods
NAME                         READY   STATUS             RESTARTS      AGE
postgres-5b5b8944c4-49kcv    1/1     Running            0             2m45s
yatri-api-544c598d56-n78tn   0/1     CrashLoopBackOff   4 (66s ago)   2m35s
```

The database is fine. The API keeps crashing.

**2. Troubleshooting commands.**

```bash
$ kubectl -n s12-troubleshoot logs deploy/yatri-api --previous
yatri-api: connecting to postgres/yatri_production_db as yatri_admin
psql: error: connection to server at "postgres" (10.101.127.77), port 5432 failed: FATAL:  password authentication failed for user "yatri_admin"
yatri-api: cannot log in to the database, exiting
$ kubectl -n s12-troubleshoot describe pod -l app=yatri-api | sed -n "/^    State/,/^    Restart Count/p"
    State:          Waiting
      Reason:       CrashLoopBackOff
    Last State:     Terminated
      Reason:       Error
      Exit Code:    1
      Started:      Wed, 07 Oct 2026 23:37:34 +0530
      Finished:     Wed, 07 Oct 2026 23:37:34 +0530
    Ready:          False
    Restart Count:  4
$ kubectl -n s12-troubleshoot logs deploy/postgres --tail=2
2026-10-07 18:07:34.334 UTC [205] FATAL:  password authentication failed for user "yatri_admin"
2026-10-07 18:07:34.334 UTC [205] DETAIL:  Connection matched file "/var/lib/postgresql/data/pg_hba.conf" line 128: "host all all all scram-sha-256"
```

Networking and DNS work (it reached `postgres` at 10.101.127.77:5432), the user name is right, and the server rejects the password. So I compared the password in the two Secrets:

```bash
$ kubectl -n s12-troubleshoot describe secret yatri-db-secret postgres-server-secret | grep -E "^Name:|PASSWORD"
Name:         yatri-db-secret
POSTGRES_PASSWORD:  15 bytes
Name:         postgres-server-secret
POSTGRES_PASSWORD:  14 bytes
$ kubectl -n s12-troubleshoot get secret yatri-db-secret -o jsonpath='{.data.POSTGRES_PASSWORD}'; echo
c2VjcmV0cGFzc3dvcmQK
$ kubectl -n s12-troubleshoot get secret yatri-db-secret -o jsonpath='{.data.POSTGRES_PASSWORD}' | base64 --decode | xxd
00000000: 7365 6372 6574 7061 7373 776f 7264 0a    secretpassword.
$ kubectl -n s12-troubleshoot get secret postgres-server-secret -o jsonpath='{.data.POSTGRES_PASSWORD}' | base64 --decode | xxd
00000000: 7365 6372 6574 7061 7373 776f 7264       secretpassword
$ echo "secretpassword" | base64; echo -n "secretpassword" | base64
c2VjcmV0cGFzc3dvcmQK
c2VjcmV0cGFzc3dvcmQ=
```

**3. Root cause.** The app's password is 15 bytes, not 14. `xxd` shows an extra `0a` byte (a newline) at the end. `echo` adds a newline unless you pass `-n`, and that newline was base64-encoded into the Secret (`...cmQK` instead of `...cmQ=`). The container got `PGPASSWORD="secretpassword\n"`, which is a different password.

**4. Fix.** [app-secret-fixed.yaml](05-troubleshooting/01-newline-secret/app-secret-fixed.yaml) has the value encoded with `echo -n`. Environment variables from a Secret are only read when a container starts, so I restarted the Deployment:

```bash
$ diff app-secret-broken.yaml app-secret-fixed.yaml
1,3c1,5
< # BROKEN on purpose: the password was encoded with plain `echo` (no -n):
< #   echo "secretpassword" | base64   ->  c2VjcmV0cGFzc3dvcmQK   (ends in "K" = encoded \n)
< # The other two values were encoded correctly with echo -n.
---
> # FIXED: password encoded with echo -n (no trailing newline)
> #   echo -n "secretpassword" | base64  ->  c2VjcmV0cGFzc3dvcmQ=
> # Even safer: let kubectl do the encoding, e.g.
> #   kubectl -n s12-troubleshoot create secret generic yatri-db-secret \
> #     --from-literal=POSTGRES_PASSWORD=... --dry-run=client -o yaml | kubectl apply -f -
11,13c13,15
<   POSTGRES_USER: eWF0cmlfYWRtaW4=                # echo -n "yatri_admin" | base64
<   POSTGRES_PASSWORD: c2VjcmV0cGFzc3dvcmQK        # echo "secretpassword" | base64   (BUG)
<   POSTGRES_DB: eWF0cmlfcHJvZHVjdGlvbl9kYg==      # echo -n "yatri_production_db" | base64
---
>   POSTGRES_USER: eWF0cmlfYWRtaW4=
>   POSTGRES_PASSWORD: c2VjcmV0cGFzc3dvcmQ=
>   POSTGRES_DB: eWF0cmlfcHJvZHVjdGlvbl9kYg==
$ kubectl apply -f app-secret-fixed.yaml
secret/yatri-db-secret configured
$ kubectl -n s12-troubleshoot describe secret yatri-db-secret | grep PASSWORD
POSTGRES_PASSWORD:  14 bytes
$ kubectl -n s12-troubleshoot rollout restart deploy/yatri-api && kubectl -n s12-troubleshoot rollout status deploy/yatri-api --timeout=120s
deployment.apps/yatri-api restarted
Waiting for deployment "yatri-api" rollout to finish: 1 old replicas are pending termination...
Waiting for deployment "yatri-api" rollout to finish: 1 old replicas are pending termination...
Waiting for deployment "yatri-api" rollout to finish: 1 old replicas are pending termination...
deployment "yatri-api" successfully rolled out
```

**5. After.**

```bash
$ kubectl -n s12-troubleshoot get pods
NAME                         READY   STATUS    RESTARTS   AGE
postgres-5b5b8944c4-49kcv    1/1     Running   0          3m10s
yatri-api-74cb9ff6f5-4cf4t   1/1     Running   0          9s
$ kubectl -n s12-troubleshoot logs deploy/yatri-api
yatri-api: connecting to postgres/yatri_production_db as yatri_admin
connected, server time 2026-10-07 18:08:57.333203+00
yatri-api: database OK, serving requests
$ kubectl -n s12-troubleshoot exec deploy/yatri-api -- sh -c 'printf %s "$PGPASSWORD" | wc -c'
14
```

| | Before | After |
| :--- | :--- | :--- |
| Pod status | `CrashLoopBackOff`, 4 restarts | `Running`, 0 restarts |
| Secret `POSTGRES_PASSWORD` | 15 bytes, base64 `c2VjcmV0cGFzc3dvcmQK` | 14 bytes, base64 `c2VjcmV0cGFzc3dvcmQ=` |
| App log | `password authentication failed` | `database OK, serving requests` |

Prevention: create Secrets with `kubectl create secret --from-literal` / `--from-file` or with `stringData`, and only use `echo -n` / `printf %s` when encoding by hand.

### Issue 2: every frontend URL returned the home page (course Ingress)

**Identify.** I applied the course file `04-full-demo/ingress.yaml` unchanged except for name, namespace and host ([ingress-course-original.yaml](05-troubleshooting/02-rewrite-target/ingress-course-original.yaml)). The frontend has two files, but asking for `/50x.html`, or for a page that does not exist, both returned the nginx welcome page with status 200:

```bash
$ kubectl apply -f ingress-course-original.yaml
ingress.networking.k8s.io/yatri-ingress-course created
$ kubectl -n s12-demo exec deploy/yatri-frontend -- ls /usr/share/nginx/html
50x.html
index.html
$ curl -s -H "Host: yatri-course.s12.local" http://localhost:18280/50x.html | grep -i "<title>"
<title>Welcome to nginx!</title>
$ curl -s -H "Host: yatri-course.s12.local" http://localhost:18280/this-page-does-not-exist | grep -i "<title>"
<title>Welcome to nginx!</title>
```

**Investigate.** The controller log shows the request as the client sent it. The frontend pod's own access log shows what it actually received:

```bash
$ kubectl -n ingress-nginx logs deploy/ingress-nginx-controller --since=2m | grep "s12-demo-yatri-frontend" | tail -2
127.0.0.1 - - [07/Oct/2026:18:10:37 +0000] "GET /50x.html HTTP/1.1" 200 615 "-" "curl/8.7.1" 93 0.007 [s12-demo-yatri-frontend-service-80] [] 10.244.0.126:80 615 0.007 200 ecadd0d6203af4aa65adbf1d5c0c57bd
127.0.0.1 - - [07/Oct/2026:18:10:37 +0000] "GET /this-page-does-not-exist HTTP/1.1" 200 615 "-" "curl/8.7.1" 109 0.001 [s12-demo-yatri-frontend-service-80] [] 10.244.0.126:80 615 0.001 200 8ba324df94ef9f48649bbe53809ed324
$ kubectl -n s12-demo logs -l app=yatri-frontend --since=2m --prefix | grep -v -E "kube-probe" | tail -2
[pod/yatri-frontend-6bfb478759-9frb8/frontend] 10.244.0.5 - - [07/Oct/2026:18:10:37 +0000] "GET / HTTP/1.1" 200 615 "-" "curl/8.7.1" "127.0.0.1"
[pod/yatri-frontend-6bfb478759-9frb8/frontend] 10.244.0.5 - - [07/Oct/2026:18:10:37 +0000] "GET / HTTP/1.1" 200 615 "-" "curl/8.7.1" "127.0.0.1"
$ kubectl -n ingress-nginx exec deploy/ingress-nginx-controller -- sh -c 'sed -n "/## start server yatri-course.s12.local/,/## end server yatri-course.s12.local/p" /etc/nginx/nginx.conf | grep -E "location ~|rewrite \""'
		location ~* "^/api(/|$)(.*)" {
			rewrite "(?i)/api(/|$)(.*)" /$2 break;
		location ~* "^/" {
			rewrite "(?i)/" /$2 break;
```

**Root cause.** The annotation `nginx.ingress.kubernetes.io/rewrite-target: /$2` applies to every path in the Ingress, not only to `/api`. The frontend path `/` has no capture groups, so `$2` is empty and every frontend request is rewritten to `/`. The pod always served `index.html`, and broken links never returned a 404.

**Fix.** Give the frontend path the same group structure: `/()(.*)`. Group 1 is empty and `$2` is the rest of the URL. This is the path in my [03-ingress/ingress-path-based.yaml](03-ingress/ingress-path-based.yaml). (Putting the rewrite in its own Ingress for `/api` only would also work.)

**After** (my fixed Ingress on `yatri.s12.local`):

```bash
$ curl -s -H "Host: yatri.s12.local" http://localhost:18280/50x.html | grep -i "<title>"
<title>Error</title>
$ curl -s -o /dev/null -w "%{http_code}\n" -H "Host: yatri.s12.local" http://localhost:18280/this-page-does-not-exist
404
$ kubectl -n s12-demo logs -l app=yatri-frontend --since=1m --prefix | grep -E "GET /(50x|this-page)"
[pod/yatri-frontend-6bfb478759-6h764/frontend] 10.244.0.5 - - [07/Oct/2026:18:10:37 +0000] "GET /50x.html HTTP/1.1" 200 497 "-" "curl/8.7.1" "127.0.0.1"
[pod/yatri-frontend-6bfb478759-6h764/frontend] 2026/10/07 18:10:37 [error] 35#35: *6 open() "/usr/share/nginx/html/this-page-does-not-exist" failed (2: No such file or directory), client: 10.244.0.5, server: localhost, request: "GET /this-page-does-not-exist HTTP/1.1", host: "yatri.s12.local"
[pod/yatri-frontend-6bfb478759-6h764/frontend] 10.244.0.5 - - [07/Oct/2026:18:10:37 +0000] "GET /this-page-does-not-exist HTTP/1.1" 404 153 "-" "curl/8.7.1" "127.0.0.1"
...
$ kubectl -n s12-demo delete ingress yatri-ingress-course orphan-ingress
ingress.networking.k8s.io "yatri-ingress-course" deleted from s12-demo namespace
ingress.networking.k8s.io "orphan-ingress" deleted from s12-demo namespace
```

Now the pod receives the real path: `/50x.html` returns the "Error" page and a missing page returns 404.

## Cleanup

```bash
$ kubectl delete namespace s12-demo s12-troubleshoot
namespace "s12-demo" deleted
namespace "s12-troubleshoot" deleted
```

The `kubectl port-forward` to the controller was stopped as well. Nothing in `ingress-nginx` was changed.

## What I learned

- ConfigMap values reach a container as env vars (read once at start) or as files (updated in place after a short delay). Changing an env value needs a Pod restart.
- A Secret is used just like a ConfigMap, but it is only base64-encoded. Its protection is RBAC, etcd encryption and keeping it out of Git (Sealed Secrets, External Secrets, SOPS, or `kubectl create secret --from-literal`).
- `echo` without `-n` adds a newline that becomes part of the secret. Comparing byte counts in `kubectl describe secret` and checking with `xxd` finds it quickly.
- An Ingress is only a set of rules. The ingress-nginx controller turns it into nginx `server`/`location` blocks, and a `Host` header or a path decides which Service gets the request.
- Ingress annotations apply to the whole Ingress object. A rewrite meant for `/api` also rewrote the frontend path, and only the pod's own access log showed it.
- On a shared cluster, use unique host names and the controller's port-forward. On a new Kubernetes version the image cache can behave differently (the per-name credential check triggered a Docker Hub pull).
