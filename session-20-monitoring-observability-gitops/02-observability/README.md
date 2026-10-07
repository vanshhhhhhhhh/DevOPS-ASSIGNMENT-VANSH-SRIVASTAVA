# Task 2: Observability

**Name:** Vansh Srivastava
**Enrollment No.:** 24bcs10567
**Session:** 20

This part covers the theory behind observability: the three pillars (metrics, logs and traces), why monitoring alone is not enough, the common tools, and how observability works in Kubernetes. I tie the theory to two real examples. First, one trace id that shows up in an HTTP response, a log line and a Prometheus exemplar of my Task 1 app. Second, the Kubernetes signals (`kubectl top`, `logs`, `events`, the metrics API and the kubelet's cAdvisor endpoint) for a small demo workload on the shared minikube cluster.

Back to the [session README](../README.md).

## Folder structure

```text
02-observability/
├── README.md                 # this file
└── k8s-demo/
    ├── namespace.yaml        # namespace s20-observability
    └── deployment.yaml       # busybox log emitter, adapted from the course repo's k8s-demo
```

## Monitoring vs observability

| | Monitoring | Observability |
|---|---|---|
| Question it answers | "Is something wrong?" | "Why is it wrong, and where?" |
| Works for | known failure modes you predicted (CPU high, app down, error rate up) | new problems nobody wrote an alert for |
| Looks like | dashboards and alert rules on a fixed set of metrics | being able to ask new questions of metrics, logs and traces after the fact |
| Example from Task 1 | `HighErrorRate` fired at 10.4% | the error logs showed 451 `simulated upstream failure` on `/api/error` and 57 `simulated database timeout` on `/api/orders` |

Monitoring is part of observability. You still need alerts to tell you something is wrong, but in a system made of many services the alert rarely tells you the cause. Observability means the system emits enough detail (rich metrics, structured logs, traces) that you can find the cause without shipping new code to debug it.

## The three pillars

### Metrics: numbers over time ("how much / how often")

A metric is a named number with labels, sampled over time, for example `app_requests_total{endpoint="/api/orders",status="500"}`. Metrics are cheap to store and fast to aggregate, which makes them the right input for dashboards and alerts. Common kinds are counters (only go up: requests, errors), gauges (go up and down: memory, in-flight requests) and histograms (distributions: latency buckets, from which you get p95/p99). The weak spot is detail: a metric tells you that 57 orders failed, not which ones. Every distinct label value creates a new time series, so you cannot put a user id or request id in a label.

### Logs: timestamped events ("what happened")

A log is a record of one event. Plain text logs are easy to write but hard to query. Structured logs (JSON with fixed fields such as `level`, `path`, `status`, `trace_id`) can be filtered and counted like data, as I did with `jq` in Task 1. Logs carry the detail metrics leave out (the error message, the request path, the user), but they are much more expensive to store and search at scale.

### Traces: the journey of one request ("where did the time go")

A trace follows a single request across every service it touches. Each step is a span with a start time, a duration and a parent span, and all spans share one trace id. The trace id travels between services in the W3C `traceparent` header (`00-<trace-id>-<span-id>-<flags>`). A trace answers questions the other two cannot, for example "the checkout call took 2 s, and 1.6 s of that was the payment service waiting on its database".

### How they work together

You usually start from a metric or an alert (something is slow), jump to the traces for slow requests to see which service or call is slow, then read that service's logs for the same trace id to see the actual error. This only works if the signals share identifiers, which is why the trace id has to appear in logs and, through exemplars, in metrics.

## Real example 1: one trace id across metrics, logs and the response

My Task 1 app ([01-monitoring/app/app.py](../01-monitoring/app/app.py)) reads an incoming `traceparent` header (or creates a trace id), writes it into its JSON log line, returns it in the response headers, and attaches it to the latency histogram as an exemplar. Prometheus runs with `--enable-feature=exemplar-storage` so it stores exemplars. I ran this from the `01-monitoring` folder while the Task 1 stack was up, sending a request with a made-up trace id `4bf92f3577b34da6a3ce929d0e0e4736`:

```bash
$ curl -s -D - -o /dev/null -H 'traceparent: 00-4bf92f3577b34da6a3ce929d0e0e4736-00f067aa0ba902b7-01' localhost:8300/api/slow | grep -iE '^(HTTP|x-trace-id|traceparent)'
HTTP/1.1 200 OK
X-Trace-Id: 4bf92f3577b34da6a3ce929d0e0e4736
traceparent: 00-4bf92f3577b34da6a3ce929d0e0e4736-f1697e43a9704718-01

$ docker compose logs app --no-log-prefix | grep 4bf92f3577b34da6a3ce929d0e0e4736 | jq .
{
  "ts": "2026-10-07T17:56:41.691Z",
  "level": "INFO",
  "service": "s20-app",
  "version": "1.0.0",
  "msg": "request completed",
  "trace_id": "4bf92f3577b34da6a3ce929d0e0e4736",
  "span_id": "f1697e43a9704718",
  "method": "GET",
  "path": "/api/slow",
  "status": 200,
  "duration_ms": 556.26,
  "client": "curl/8.7.1",
  "parent_span_id": "00f067aa0ba902b7"
}

$ curl -s -H 'Accept: application/openmetrics-text' localhost:8300/metrics | grep 4bf92f3577b34da6a3ce929d0e0e4736
app_request_duration_seconds_bucket{endpoint="/api/slow",le="1.0"} 188.0 # {trace_id="4bf92f3577b34da6a3ce929d0e0e4736"} 0.5562595670000974 1791395801.691033

$ curl -s localhost:9390/api/v1/query_exemplars --data-urlencode 'query=app_request_duration_seconds_bucket{endpoint="/api/slow"}' --data-urlencode "start=$(date -v-2M +%s)" --data-urlencode "end=$(date +%s)" | jq -c '.data[] | .exemplars[] | select(.labels.trace_id=="4bf92f3577b34da6a3ce929d0e0e4736")'
{"labels":{"trace_id":"4bf92f3577b34da6a3ce929d0e0e4736"},"value":"0.5562595670000974","timestamp":1791395801.691}
```

The same request shows up in four places:

1. **Response:** the app kept the caller's trace id and created its own span id (`f1697e43a9704718`), so the trace continues through it.
2. **Log:** the JSON log line has the same `trace_id`, the caller's span as `parent_span_id`, and the duration (556 ms).
3. **Metric:** in the latency histogram, the `le="1.0"` bucket carries this request as its exemplar (value 0.556 s, same trace id). The exemplar only appears in the OpenMetrics format, which is what Prometheus asks for.
4. **Prometheus:** `query_exemplars` returns it, so from a latency spike on a graph you can jump to the exact trace id and then to the log line.

What is missing to make this a full tracing setup: the app does not send spans to a tracing backend. A real setup would use the OpenTelemetry SDK to export spans to Jaeger or Tempo, and Grafana would link the exemplar to the trace view. The ids and the propagation are the same either way.

## Why observability is needed

- **Distributed systems fail in new ways.** With dozens of services, queues and caches, most incidents are combinations nobody predicted, so no prewritten alert covers them. You need data that lets you ask new questions.
- **Averages hide problems.** A healthy average latency can hide a p99 of several seconds for one customer or one endpoint. Histograms, high-detail logs and traces show the tail.
- **Faster recovery.** Mean time to recovery is mostly time spent finding the cause. Correlated signals (alert, then metric, then trace, then log) shorten that search.
- **Change is constant.** With many deploys a day you need to see quickly whether a release made things worse (for example `app_build_info{version}` next to error rate).
- **SLOs and capacity.** Error budgets, latency SLOs and capacity planning all depend on good metrics.

## Common tools

| Tool | Pillar | What it does |
|---|---|---|
| **Prometheus** | metrics | pull-based scraping, time-series database, PromQL, alert rules (used in Task 1) |
| **Alertmanager** | alerts | groups, de-duplicates, silences and routes Prometheus alerts to Slack, email, PagerDuty, webhooks (used in Task 1) |
| **Grafana** | visualisation | dashboards over Prometheus, Loki, Tempo, Elasticsearch and more; can link metrics to logs and traces (used in Task 1) |
| **Loki** | logs | log store from Grafana Labs that indexes only labels, not full text, so it is cheap; queried with LogQL |
| **ELK / Elastic Stack** | logs | Elasticsearch (search and storage), Logstash or Beats/Fluent Bit (shipping and parsing), Kibana (UI); full-text search over logs |
| **Fluent Bit / Fluentd** | logs | agents that collect container logs from nodes and ship them to Loki, Elasticsearch, etc. |
| **Jaeger** | traces | distributed tracing backend and UI (CNCF) |
| **Tempo** | traces | Grafana's trace store; cheap object storage, looked up by trace id, linked from exemplars |
| **OpenTelemetry** | all three | vendor-neutral standard: SDKs for instrumenting code, the OTLP protocol, and the Collector that receives, processes and exports metrics, logs and traces to any backend |
| **cAdvisor** | metrics | container CPU/memory/network/filesystem usage (standalone in Task 1, built into the kubelet in Kubernetes) |

## Kubernetes observability

| Piece | What it provides | How you use it |
|---|---|---|
| **cAdvisor (in the kubelet)** | per-container CPU, memory, network, filesystem usage | Prometheus scrapes `/metrics/cadvisor` on each kubelet; the source behind `container_*` metrics |
| **metrics-server** | short-term CPU/memory usage for nodes and pods, from the kubelets, served through the `metrics.k8s.io` API | `kubectl top`, and the Horizontal Pod Autoscaler; not a long-term store |
| **kube-state-metrics** | metrics about Kubernetes objects: desired vs available replicas, pod phase, restarts, job status | scraped by Prometheus, e.g. alert when `kube_deployment_status_replicas_available < kube_deployment_spec_replicas` |
| **kubectl logs** | container stdout/stderr (`--previous` for a crashed container) | first stop when a pod misbehaves |
| **kubectl get events / describe** | what the control plane did: scheduling, image pulls, probe failures, OOM kills, scaling | explains why a pod is Pending, CrashLoopBackOff, etc. |
| **Prometheus Operator / kube-prometheus-stack** | runs Prometheus, Alertmanager, Grafana, node-exporter and kube-state-metrics in-cluster, configured through CRDs (`ServiceMonitor`, `PodMonitor`, `PrometheusRule`) | lets each team declare "scrape my service" and "alert on this" as YAML next to their app |

The shared minikube cluster has the metrics-server addon. It has no kube-state-metrics or Prometheus Operator (no `monitoring.coreos.com` CRDs, see below), so those two rows are documented only. I did not install a cluster-wide monitoring stack on a cluster other people are using.

## Real example 2: observing a pod on the shared cluster

The course repo's `02-metrics-logs-traces/k8s-demo/deployment.yaml` (Nency-Ravaliya/devops-heros) is a busybox container that prints "Request received" / "Health check OK" in a loop. I adapted it in [k8s-demo/deployment.yaml](k8s-demo/deployment.yaml): it runs in my own namespace `s20-observability`, has small CPU and memory requests and limits, prints JSON lines with a random `trace_id`, and pulls busybox from the AWS ECR mirror. I left out the course repo's Service because nothing in the pod listens on a port.

```bash
$ kubectl apply -f k8s-demo/namespace.yaml -f k8s-demo/deployment.yaml
namespace/s20-observability created
deployment.apps/s20-obs-demo created

$ kubectl rollout status deployment/s20-obs-demo -n s20-observability --timeout=120s
Waiting for deployment "s20-obs-demo" rollout to finish: 0 of 1 updated replicas are available...
deployment "s20-obs-demo" successfully rolled out

$ kubectl get pods -n s20-observability -o wide
NAME                           READY   STATUS    RESTARTS   AGE   IP            NODE       NOMINATED NODE   READINESS GATES
s20-obs-demo-d5d9c7b47-4f2gz   1/1     Running   0          5s    10.244.0.54   minikube   <none>           <none>
```

**Metrics** (metrics-server, through `kubectl top`, a few minutes later):

```bash
$ kubectl top nodes
NAME       CPU(cores)   CPU(%)   MEMORY(bytes)   MEMORY(%)
minikube   521m         8%       2178Mi          21%

$ kubectl top pods -n s20-observability --containers
POD                            NAME   CPU(cores)   MEMORY(bytes)
s20-obs-demo-d5d9c7b47-4f2gz   app    1m           0Mi

$ kubectl top pods -n argocd --sort-by=memory
NAME                                                CPU(cores)   MEMORY(bytes)
argocd-server-776b7cdd4d-9flrm                      1m           23Mi
argocd-application-controller-0                     2m           23Mi
argocd-repo-server-d89c7967d-44f8t                  2m           20Mi
argocd-applicationset-controller-76fd8cdd4f-gzfd4   1m           19Mi
argocd-dex-server-66c78cf887-f79bn                  1m           18Mi
argocd-notifications-controller-7fb9868fd6-2vxwm    1m           16Mi
argocd-redis-bdbdffcb4-rjkfh                        4m           4Mi
```

`kubectl top` reads the `metrics.k8s.io` API, which metrics-server provides. The raw API shows where the numbers come from: a usage sample over a window of about one minute.

```bash
$ kubectl get apiservice v1beta1.metrics.k8s.io
NAME                     SERVICE                      AVAILABLE   AGE
v1beta1.metrics.k8s.io   kube-system/metrics-server   True        22m

$ kubectl get deploy -n kube-system metrics-server
NAME             READY   UP-TO-DATE   AVAILABLE   AGE
metrics-server   1/1     1            1           22m

$ kubectl get --raw /apis/metrics.k8s.io/v1beta1/namespaces/s20-observability/pods | jq -c '.items[] | {pod: .metadata.name, window, usage: .containers[0].usage}'
{"pod":"s20-obs-demo-d5d9c7b47-4f2gz","window":"1m2.114s","usage":{"cpu":"577196n","memory":"344Ki"}}
```

The pod uses about 0.58 millicores and 344 KiB, which `kubectl top` rounds to `1m` and `0Mi`. The kubelet's built-in cAdvisor exposes the same data in Prometheus format. This is the endpoint a Prometheus in the cluster would scrape:

```bash
$ kubectl get --raw /api/v1/nodes/minikube/proxy/metrics/cadvisor | grep -E '^container_memory_working_set_bytes.*namespace="s20-observability"'
container_memory_working_set_bytes{container="",id="/kubepods/burstable/pod69353589-c306-427c-972b-70fb57f67306",image="",name="",namespace="s20-observability",pod="s20-obs-demo-d5d9c7b47-4f2gz"} 598016 1791395985191
container_memory_working_set_bytes{container="",id="/kubepods/burstable/pod69353589-c306-427c-972b-70fb57f67306/fc707a2816ac59e310d15779d94f171e0329d2665ce95a799cf17f6b0a0a631f",image="registry.k8s.io/pause:3.10.2",name="fc707a2816ac59e310d15779d94f171e0329d2665ce95a799cf17f6b0a0a631f",namespace="s20-observability",pod="s20-obs-demo-d5d9c7b47-4f2gz"} 212992 1791395979468
container_memory_working_set_bytes{container="app",id="/kubepods/burstable/pod69353589-c306-427c-972b-70fb57f67306/16faefd19b0a42ded34ff30d10c9ab75e045d486c6daebc879f5371199f751f7",image="docker.io/library/busybox:1.36",name="16faefd19b0a42ded34ff30d10c9ab75e045d486c6daebc879f5371199f751f7",namespace="s20-observability",pod="s20-obs-demo-d5d9c7b47-4f2gz"} 352256 1791395979513
```

There are three series: the whole pod cgroup, the pause (sandbox) container and my `app` container. This is the same `container_memory_working_set_bytes` metric that the standalone cAdvisor gave me in Task 1, but here it has Kubernetes labels (`namespace`, `pod`, `container`).

**Logs:**

```bash
$ kubectl logs deployment/s20-obs-demo -n s20-observability --tail=4
{"level":"INFO","msg":"Request received","request_no":31,"trace_id":"a434e4b9c7df4f46d05b53300e1612e2"}
{"level":"INFO","msg":"Health check OK","request_no":31}
{"level":"INFO","msg":"Request received","request_no":32,"trace_id":"8a1dc7b59ceb9541cfbc1028615535f6"}
{"level":"INFO","msg":"Health check OK","request_no":32}

$ kubectl logs deployment/s20-obs-demo -n s20-observability --tail=2 | jq -c 'select(.trace_id) | {msg, request_no, trace_id}'
{"msg":"Request received","request_no":32,"trace_id":"8a1dc7b59ceb9541cfbc1028615535f6"}
```

**Events and describe** (what Kubernetes itself did):

```bash
$ kubectl get events -n s20-observability --sort-by=.lastTimestamp
LAST SEEN   TYPE     REASON              OBJECT                              MESSAGE
5m14s       Normal   Scheduled           pod/s20-obs-demo-d5d9c7b47-4f2gz    Successfully assigned s20-observability/s20-obs-demo-d5d9c7b47-4f2gz to minikube
5m14s       Normal   SuccessfulCreate    replicaset/s20-obs-demo-d5d9c7b47   Created pod: s20-obs-demo-d5d9c7b47-4f2gz
5m14s       Normal   ScalingReplicaSet   deployment/s20-obs-demo             Scaled up replica set s20-obs-demo-d5d9c7b47 from 0 to 1
5m13s       Normal   Pulling             pod/s20-obs-demo-d5d9c7b47-4f2gz    Pulling image "public.ecr.aws/docker/library/busybox:1.36"
5m9s        Normal   Pulled              pod/s20-obs-demo-d5d9c7b47-4f2gz    Successfully pulled image "public.ecr.aws/docker/library/busybox:1.36" in 3.381s (3.381s including waiting). Image size: 1897169 bytes.
5m9s        Normal   Created             pod/s20-obs-demo-d5d9c7b47-4f2gz    Container created
5m9s        Normal   Started             pod/s20-obs-demo-d5d9c7b47-4f2gz    Container started

$ kubectl describe deployment s20-obs-demo -n s20-observability | sed -n '1,12p;/Conditions/,$p'
Name:                   s20-obs-demo
Namespace:              s20-observability
CreationTimestamp:      Wed, 07 Oct 2026 23:24:33 +0530
Labels:                 app=s20-obs-demo
Annotations:            deployment.kubernetes.io/revision: 1
Selector:               app=s20-obs-demo
Replicas:               1 desired | 1 updated | 1 total | 1 available | 0 unavailable
StrategyType:           RollingUpdate
MinReadySeconds:        0
RollingUpdateStrategy:  25% max unavailable, 25% max surge
Pod Template:
  Labels:  app=s20-obs-demo
Conditions:
  Type           Status  Reason
  ----           ------  ------
  Available      True    MinimumReplicasAvailable
  Progressing    True    NewReplicaSetAvailable
OldReplicaSets:  <none>
NewReplicaSet:   s20-obs-demo-d5d9c7b47 (1/1 replicas created)
Events:
  Type    Reason             Age    From                   Message
  ----    ------             ----   ----                   -------
  Normal  ScalingReplicaSet  5m14s  deployment-controller  Scaled up replica set s20-obs-demo-d5d9c7b47 from 0 to 1
```

The events read like a short trace of the control plane. The Deployment controller scaled the ReplicaSet, the ReplicaSet created the pod, the scheduler placed it, the kubelet pulled the image (3.4 s) and started the container. When a pod is stuck, this is where the reason shows up (FailedScheduling, ErrImagePull, probe failures, OOMKilled).

No Prometheus Operator is installed on this cluster:

```bash
$ kubectl get crd | grep -c monitoring.coreos.com || true
0
```

Cleanup:

```bash
$ kubectl delete -f k8s-demo/deployment.yaml -f k8s-demo/namespace.yaml
deployment.apps "s20-obs-demo" deleted from s20-observability namespace
namespace "s20-observability" deleted
```

## Summary

```text
Metrics -> how much / how often   (Prometheus, metrics-server, cAdvisor, kube-state-metrics)
Logs    -> what happened          (kubectl logs, docker compose logs, Loki, ELK)
Traces  -> where the time went    (OpenTelemetry -> Jaeger / Tempo)
Shared ids (trace_id) connect them: alert -> metric/exemplar -> trace -> log line.
```
