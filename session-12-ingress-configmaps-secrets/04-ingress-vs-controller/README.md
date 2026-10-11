# Ingress vs Ingress Controller

**Name:** Vansh Srivastava
**Enrollment No.:** 24bcs10567
**Session:** 12, Task 4

All outputs below are from the shared minikube cluster (Kubernetes v1.37.0, minikube `ingress` addon), taken while the Ingresses from Task 3 were deployed in namespace `s12-demo`.

## What is an Ingress?

An Ingress is a Kubernetes API object (`apiVersion: networking.k8s.io/v1`, `kind: Ingress`) that describes how HTTP(S) traffic from outside should reach Services inside the cluster:

- **rules**: which host name and which URL path goes to which Service and port
- **tls**: which Secret holds the certificate for which host
- **ingressClassName**: which controller should implement it
- **annotations**: controller-specific options, such as `nginx.ingress.kubernetes.io/rewrite-target`

An Ingress is only data. Creating one does not open a port or start a process. My [ingress-path-based.yaml](../03-ingress/ingress-path-based.yaml) says "host `yatri.s12.local`, `/api/...` to `yatri-backend-service:80`, everything else to `yatri-frontend-service:80`", and that is all it does.

## What is an Ingress Controller?

An Ingress Controller is a program running in the cluster. It watches Ingress objects (and the Services and EndpointSlices they point to) and configures a real reverse proxy or load balancer to match them. It is also what actually receives the traffic. Examples are ingress-nginx (used here), Traefik, HAProxy Ingress, the AWS Load Balancer Controller (creates an ALB), GKE Ingress (creates a Google HTTP(S) load balancer) and Istio's ingress gateway.

On this cluster the controller is the minikube addon:

```bash
$ kubectl -n ingress-nginx get deploy,pods,svc -o wide
NAME                                       READY   UP-TO-DATE   AVAILABLE   AGE   CONTAINERS   IMAGES                                                                                                                     SELECTOR
deployment.apps/ingress-nginx-controller   1/1     1            1           26m   controller   registry.k8s.io/ingress-nginx/controller:v1.15.1@sha256:594ceea76b01c592858f803f9ff4d2cb40542cae2060410b2c95f75907d659e1   app.kubernetes.io/component=controller,app.kubernetes.io/instance=ingress-nginx,app.kubernetes.io/name=ingress-nginx

NAME                                           READY   STATUS      RESTARTS   AGE   IP           NODE       NOMINATED NODE   READINESS GATES
pod/ingress-nginx-admission-create-9m6c7       0/1     Completed   0          26m   10.244.0.3   minikube   <none>           <none>
pod/ingress-nginx-admission-patch-zp68c        0/1     Completed   0          26m   10.244.0.4   minikube   <none>           <none>
pod/ingress-nginx-controller-d7cd8c989-5zg8b   1/1     Running     0          26m   10.244.0.5   minikube   <none>           <none>

NAME                                         TYPE        CLUSTER-IP      EXTERNAL-IP   PORT(S)                      AGE   SELECTOR
service/ingress-nginx-controller             NodePort    10.103.16.6     <none>        80:31119/TCP,443:32766/TCP   26m   app.kubernetes.io/component=controller,app.kubernetes.io/instance=ingress-nginx,app.kubernetes.io/name=ingress-nginx
service/ingress-nginx-controller-admission   ClusterIP   10.105.71.208   <none>        443/TCP                      26m   app.kubernetes.io/component=controller,app.kubernetes.io/instance=ingress-nginx,app.kubernetes.io/name=ingress-nginx
$ kubectl -n ingress-nginx get deploy ingress-nginx-controller -o jsonpath='{.spec.template.spec.containers[0].image}{"\n"}{range .spec.template.spec.containers[0].args[*]}{@}{"\n"}{end}'
registry.k8s.io/ingress-nginx/controller:v1.15.1@sha256:594ceea76b01c592858f803f9ff4d2cb40542cae2060410b2c95f75907d659e1
/nginx-ingress-controller
--election-id=ingress-nginx-leader
--controller-class=k8s.io/ingress-nginx
--watch-ingress-without-class=true
--configmap=$(POD_NAMESPACE)/ingress-nginx-controller
--tcp-services-configmap=$(POD_NAMESPACE)/tcp-services
--udp-services-configmap=$(POD_NAMESPACE)/udp-services
--validating-webhook=:8443
--validating-webhook-certificate=/usr/local/certificates/cert
--validating-webhook-key=/usr/local/certificates/key
```

- One controller pod runs nginx plus the watch loop. On a cloud cluster its Service would be `type: LoadBalancer` (one cloud load balancer for every app). minikube uses a NodePort, and I reached it with `kubectl port-forward`.
- `--controller-class=k8s.io/ingress-nginx` is how this controller recognises the Ingresses it owns.
- The two `admission` pods are one-off Jobs that set up the validating webhook. The webhook checks every Ingress before the API server stores it.

## How they are connected: IngressClass

```bash
$ kubectl get ingressclass
NAME              CONTROLLER             PARAMETERS   AGE
nginx (default)   k8s.io/ingress-nginx   <none>       26m
$ kubectl get ingressclass nginx -o yaml | grep -vE "^\s+(resourceVersion|uid|creationTimestamp|generation):"
apiVersion: networking.k8s.io/v1
kind: IngressClass
metadata:
  annotations:
    ingressclass.kubernetes.io/is-default-class: "true"
    kubectl.kubernetes.io/last-applied-configuration: |
      {"apiVersion":"networking.k8s.io/v1","kind":"IngressClass","metadata":{"annotations":{"ingressclass.kubernetes.io/is-default-class":"true"},"labels":{"app.kubernetes.io/component":"controller","app.kubernetes.io/instance":"ingress-nginx","app.kubernetes.io/name":"ingress-nginx"},"name":"nginx"},"spec":{"controller":"k8s.io/ingress-nginx"}}
  labels:
    app.kubernetes.io/component: controller
    app.kubernetes.io/instance: ingress-nginx
    app.kubernetes.io/name: ingress-nginx
  name: nginx
spec:
  controller: k8s.io/ingress-nginx
```

My Ingress says `ingressClassName: nginx`. The IngressClass `nginx` says its controller is `k8s.io/ingress-nginx`, and that matches the controller's `--controller-class` flag. That is how one cluster can run several controllers side by side (for example an internal and a public one).

## The controller turning my Ingress into nginx config

When I applied my Ingress, the controller validated it, found the IngressClass, wrote it into its nginx config and set the Ingress status (that is where `ADDRESS` comes from):

```bash
$ kubectl -n ingress-nginx logs deploy/ingress-nginx-controller --since=60m | grep -E "s12-demo/yatri-ingress|ingress=\"yatri-ingress\"" | grep -E "accepting|IngressClass|updating Ingress status" | head -4
I1007 18:02:25.855195       7 main.go:107] "successfully validated configuration, accepting" ingress="s12-demo/yatri-ingress"
I1007 18:02:25.863423       7 store.go:443] "Found valid IngressClass" ingress="s12-demo/yatri-ingress" ingressclass="nginx"
I1007 18:02:37.050434       7 status.go:311] "updating Ingress status" namespace="s12-demo" ingress="yatri-ingress" currentValue=null newValue=[{"ip":"192.168.49.2"}]
```

Inside the controller pod, each host from my two Ingresses became an nginx `server` block, and each path became a `location` with an upstream named after the namespace, Service and port (read-only `exec`, nothing changed):

```bash
$ kubectl -n ingress-nginx exec deploy/ingress-nginx-controller -- grep -n "server_name \"[a-z]*\.s12\.local\"" /etc/nginx/nginx.conf
337:		server_name "api.s12.local" ;
452:		server_name "web.s12.local" ;
567:		server_name "yatri.s12.local" ;
$ kubectl -n ingress-nginx exec deploy/ingress-nginx-controller -- sh -c 'sed -n "/## start server yatri.s12.local/,/## end server yatri.s12.local/p" /etc/nginx/nginx.conf | grep -E "location ~|proxy_upstream_name \"s12|rewrite \"|proxy_pass"'
		location ~* "^/api(/|$)(.*)" {
			set $proxy_upstream_name "s12-demo-yatri-backend-service-80";
			rewrite "(?i)/api(/|$)(.*)" /$2 break;
			proxy_pass http://upstream_balancer;
		location ~* "^/()(.*)" {
			set $proxy_upstream_name "s12-demo-yatri-frontend-service-80";
			rewrite "(?i)/()(.*)" /$2 break;
			proxy_pass http://upstream_balancer;
...
```

The access log shows real requests going through those upstreams straight to pod IPs. ingress-nginx sends traffic to the endpoints directly instead of through the Service's ClusterIP:

```bash
$ kubectl -n ingress-nginx logs deploy/ingress-nginx-controller --since=60m | grep -E "\[s12-demo-yatri-(frontend|backend)-service-80\]" | head -3
127.0.0.1 - - [07/Oct/2026:18:02:38 +0000] "GET / HTTP/1.1" 200 615 "-" "curl/8.7.1" 78 0.003 [s12-demo-yatri-frontend-service-80] [] 10.244.0.127:80 615 0.003 200 9045f43f064a9f9bbdb4c3b8a54918e4
127.0.0.1 - - [07/Oct/2026:18:02:38 +0000] "GET /api/ HTTP/1.1" 200 247 "-" "curl/8.7.1" 82 0.004 [s12-demo-yatri-backend-service-80] [] 10.244.0.129:5000 247 0.004 200 e34212d7c40cac068264686a91daadb8
127.0.0.1 - - [07/Oct/2026:18:02:38 +0000] "GET /api/bookings/42 HTTP/1.1" 200 258 "-" "curl/8.7.1" 93 0.001 [s12-demo-yatri-backend-service-80] [] 10.244.0.129:5000 258 0.000 200 c1bca4b19380d05cb483ff5d5a5b790c
```

## Experiment: an Ingress without a controller

[ingress-no-controller.yaml](ingress-no-controller.yaml) is a normal Ingress for `orphan.s12.local`, except that it asks for the class `s12-no-such-class`, which no controller implements:

```bash
$ kubectl apply -f 04-ingress-vs-controller/ingress-no-controller.yaml
ingress.networking.k8s.io/orphan-ingress created
$ kubectl -n s12-demo get ingress
NAME                 CLASS               HOSTS                         ADDRESS        PORTS   AGE
orphan-ingress       s12-no-such-class   orphan.s12.local                             80      20s
yatri-host-ingress   nginx               web.s12.local,api.s12.local   192.168.49.2   80      118s
yatri-ingress        nginx               yatri.s12.local               192.168.49.2   80      2m26s
$ curl -s -o /dev/null -w "orphan.s12.local -> HTTP %{http_code}\n" -H "Host: orphan.s12.local" http://localhost:18280/
orphan.s12.local -> HTTP 404
$ kubectl -n ingress-nginx exec deploy/ingress-nginx-controller -- grep -c "orphan.s12.local" /etc/nginx/nginx.conf
0
command terminated with exit code 1
$ kubectl -n s12-demo describe ingress orphan-ingress | sed -n "/^Events/,\$p"
Events:             <none>
$ kubectl -n ingress-nginx logs deploy/ingress-nginx-controller --since=5m | grep orphan | head -3
W1007 18:04:31.756506       7 controller.go:352] ignoring ingress orphan-ingress in s12-demo based on annotation : no object matching key "s12-no-such-class" in local store
I1007 18:04:31.756580       7 main.go:107] "successfully validated configuration, accepting" ingress="s12-demo/orphan-ingress"
I1007 18:04:31.759537       7 store.go:439] "Ignoring ingress because of error while validating ingress class" ingress="s12-demo/orphan-ingress" error="no object matching key \"s12-no-such-class\" in local store"
```

The API server accepted the object (it is valid YAML and a valid Ingress), but it has no ADDRESS, it is not in `nginx.conf`, the controller logs "Ignoring ingress", and the host returns 404. An Ingress on its own does nothing.

## The difference, side by side

| | Ingress | Ingress Controller |
| :--- | :--- | :--- |
| Kind of thing | API object (YAML stored in etcd) | Deployment/DaemonSet running a proxy |
| Who writes it | Application teams, one or more per app | Cluster admins, installed once (Helm, addon, cloud) |
| Namespace | The app's namespace (`s12-demo`) | Its own namespace (`ingress-nginx`) |
| Handles packets | No | Yes, all external HTTP(S) traffic goes through it |
| Without the other | Ignored, no ADDRESS, 404 (experiment above) | Runs, but serves only its default 404 backend |
| Portable? | Mostly yes (`rules`, `tls`); annotations are controller-specific | Each controller has its own features and annotations |

## Why both are required

Kubernetes separates the "what" from the "how". The Ingress API is the same on every cluster, so an app team can describe its routing without knowing which proxy runs underneath. The controller is the part that depends on the platform: nginx on minikube, an AWS ALB on EKS, a Google load balancer on GKE. The Ingress is the routing table and the controller is the router that loads it and forwards the packets. Without the rules the controller has nothing to route, and without the controller the rules are never applied.
