# Kubernetes Volumes: emptyDir, hostPath, PV, PVC, StorageClass

**Name:** Vansh Srivastava
**Enrollment No.:** 24bcs10567
**Session:** 13, Task 1

A container's own filesystem is thrown away when the container is replaced. Volumes give it storage with a different lifetime: as long as the Pod (emptyDir), as long as the node (hostPath), or independent of Pods altogether (PersistentVolume). Every example below was applied on the shared minikube cluster (Kubernetes v1.37.0) in my namespace `s13-volumes`. Cluster-scoped objects (PVs, StorageClass, RBAC) are prefixed `s13-` and were deleted at the end. The examples start from the course files in https://github.com/Nency-Ravaliya/devops-heros (`session-13-storage-hpa-probes/01-volumes`, `02-persistent-storage`, `03-storageclass`).

| File | What it shows |
| :--- | :--- |
| [namespace.yaml](namespace.yaml) | namespace `s13-volumes` |
| [01-emptydir-shared.yaml](01-emptydir-shared.yaml) | emptyDir shared by two containers in one Pod |
| [02-hostpath-pod.yaml](02-hostpath-pod.yaml) | hostPath (course `hostpath-pod.yaml`) |
| [course-original/](course-original/) | the course PV + PVC, used to show a binding problem |
| [03-static-pv.yaml](03-static-pv.yaml), [03-static-pvc.yaml](03-static-pvc.yaml), [03-static-pod.yaml](03-static-pod.yaml) | static provisioning, data surviving Pod deletion, Retain policy |
| [04-dynamic-pvc.yaml](04-dynamic-pvc.yaml) | dynamic provisioning with the `standard` StorageClass |
| [05-storageclass-wffc.yaml](05-storageclass-wffc.yaml), [05-wffc-pod.yaml](05-wffc-pod.yaml), [05-provisioner-rbac-fix.yaml](05-provisioner-rbac-fix.yaml) | my own StorageClass with `WaitForFirstConsumer` (and the RBAC problem it hit) |

## 1. emptyDir

`emptyDir` is an empty directory created when the Pod is scheduled. Every container in the Pod can mount it, and it is deleted when the Pod is deleted. It survives container restarts, not Pod deletion. It is used for scratch space, caches, and for passing files between containers in the same Pod (sidecars).

[01-emptydir-shared.yaml](01-emptydir-shared.yaml) extends the course `emptydir-pod.yaml`. A `writer` container (busybox) appends a line to `/data/index.html` every 5 seconds, and a `web` container (nginx) serves the same emptyDir, read-only, as its web root.

```bash
$ kubectl apply -f namespace.yaml -f 01-emptydir-shared.yaml
namespace/s13-volumes created
pod/emptydir-demo created
$ kubectl -n s13-volumes wait --for=condition=Ready pod/emptydir-demo --timeout=120s
pod/emptydir-demo condition met
$ kubectl -n s13-volumes get pod emptydir-demo
NAME            READY   STATUS    RESTARTS   AGE
emptydir-demo   2/2     Running   0          13s
$ kubectl -n s13-volumes exec emptydir-demo -c web -- curl -s localhost
<h1>emptyDir demo, pod emptydir-demo</h1>
<p>writer: 18:12:16</p>
<p>writer: 18:12:21</p>
<p>writer: 18:12:26</p>
$ kubectl -n s13-volumes exec emptydir-demo -c writer -- ls -l /data
total 4
-rw-r--r--    1 root     root           114 Oct  7 18:12 index.html
$ kubectl -n s13-volumes exec emptydir-demo -c web -- sh -c "mount | grep /usr/share/nginx/html"
/dev/vdb1 on /usr/share/nginx/html type ext4 (ro,relatime)
```

The file written by `writer` is served by `web`. On the node, the emptyDir is just a directory on the node's disk (`/dev/vdb1`), mounted read-only into `web`. Deleting the Pod deletes it:

```bash
$ kubectl -n s13-volumes delete pod emptydir-demo && kubectl apply -f 01-emptydir-shared.yaml
pod "emptydir-demo" deleted from s13-volumes namespace
pod/emptydir-demo created
$ kubectl -n s13-volumes wait --for=condition=Ready pod/emptydir-demo --timeout=120s
pod/emptydir-demo condition met
$ kubectl -n s13-volumes exec emptydir-demo -c web -- curl -s localhost
<h1>emptyDir demo, pod emptydir-demo</h1>
<p>writer: 18:12:59</p>
```

Only the new line is there. The three older lines went away with the old Pod.

## 2. hostPath

`hostPath` mounts a directory of the node into the Pod. The data outlives the Pod, but it is tied to that one node: a Pod scheduled on another node sees a different (empty) directory. It also gives the Pod access to the node's filesystem, which is a security risk. Use it for node agents (log collectors, CNI, monitoring) and for single-node labs, not for application data.

[02-hostpath-pod.yaml](02-hostpath-pod.yaml) is the course file with the directory renamed to `/tmp/s13-hostpath-data`, because the node is shared:

```bash
$ kubectl apply -f 02-hostpath-pod.yaml
pod/hostpath-demo created
$ kubectl -n s13-volumes wait --for=condition=Ready pod/hostpath-demo --timeout=120s
pod/hostpath-demo condition met
$ kubectl -n s13-volumes exec hostpath-demo -- sh -c "echo \"written by \$(hostname) at \$(date -u +%H:%M:%S)\" > /data/message.txt; cat /data/message.txt"
written by hostpath-demo at 18:13:08
$ minikube ssh -- cat /tmp/s13-hostpath-data/message.txt
written by hostpath-demo at 18:13:08
$ kubectl -n s13-volumes delete pod hostpath-demo && kubectl apply -f 02-hostpath-pod.yaml
pod "hostpath-demo" deleted from s13-volumes namespace
pod/hostpath-demo created
$ kubectl -n s13-volumes wait --for=condition=Ready pod/hostpath-demo --timeout=120s
pod/hostpath-demo condition met
$ kubectl -n s13-volumes exec hostpath-demo -- cat /data/message.txt
written by hostpath-demo at 18:13:08
```

The file is visible from the node itself (`minikube ssh`) and is still there for the new Pod.

## 3. PersistentVolume (PV) and PersistentVolumeClaim (PVC)

- A **PersistentVolume** is a piece of storage in the cluster (a cloud disk, an NFS export, or here a hostPath on the minikube node). It is cluster-scoped and has a capacity, access modes and a reclaim policy.
- A **PersistentVolumeClaim** is a namespaced request for storage ("500Mi, ReadWriteOnce"). Kubernetes binds it to a matching PV, and the Pod only refers to the claim, never to the PV directly.
- Access modes: `ReadWriteOnce` (read-write on one node), `ReadOnlyMany`, `ReadWriteMany`, `ReadWriteOncePod` (one Pod only).
- Reclaim policy: what happens to the PV when its claim is deleted. `Retain` keeps the data and the PV becomes `Released`. `Delete` removes the PV and its storage.

### First try with the course files: the PVC did not use my PV

I applied the course `pv.yaml` / `pvc.yaml` as they are (only renamed, see [course-original/](course-original/)):

```bash
$ kubectl apply -f course-original/pv.yaml -f course-original/pvc.yaml
persistentvolume/s13-course-student-pv created
persistentvolumeclaim/course-student-pvc created
$ kubectl get pv s13-course-student-pv
NAME                    CAPACITY   ACCESS MODES   RECLAIM POLICY   STATUS      CLAIM   STORAGECLASS   VOLUMEATTRIBUTESCLASS   REASON   AGE
s13-course-student-pv   1Gi        RWO            Retain           Available                          <unset>                          5s
$ kubectl -n s13-volumes get pvc course-student-pvc
NAME                 STATUS   VOLUME                                     CAPACITY   ACCESS MODES   STORAGECLASS   VOLUMEATTRIBUTESCLASS   AGE
course-student-pvc   Bound    pvc-fad9296c-b616-4a94-beb8-15f9ba20b084   500Mi      RWO            standard       <unset>                 5s
$ kubectl -n s13-volumes get pvc course-student-pvc -o jsonpath='{.spec.storageClassName}{"\n"}'
standard
$ kubectl -n s13-volumes describe pvc course-student-pvc | sed -n "/^Events/,\$p"
Events:
  Type    Reason                 Age              From                                                                    Message
  ----    ------                 ----             ----                                                                    -------
  Normal  ExternalProvisioning   5s (x2 over 5s)  persistentvolume-controller                                             Waiting for a volume to be created either by the external provisioner 'k8s.io/minikube-hostpath' or manually by the system administrator. If volume creation is delayed, please verify that the provisioner is running and correctly registered.
  Normal  Provisioning           5s               k8s.io/minikube-hostpath_minikube_7ea85d63-39ab-4d87-8315-0e7b0631c27c  External provisioner is provisioning volume for claim "s13-volumes/course-student-pvc"
  Normal  ProvisioningSucceeded  5s               k8s.io/minikube-hostpath_minikube_7ea85d63-39ab-4d87-8315-0e7b0631c27c  Successfully provisioned volume pvc-fad9296c-b616-4a94-beb8-15f9ba20b084
$ kubectl delete -f course-original/pvc.yaml -f course-original/pv.yaml
persistentvolumeclaim "course-student-pvc" deleted from s13-volumes namespace
persistentvolume "s13-course-student-pv" deleted
```

The PVC was Bound, but to a new, dynamically created volume, and the hand-made PV stayed `Available`. The cause: the PVC has no `storageClassName`, and the cluster has a default StorageClass, so the API server filled in `standard`. The PV has no class (`""`), so the two can never match. With a default StorageClass present, a static PV and its PVC must both set `storageClassName: ""` (or the same class name).

### Static provisioning, fixed

[03-static-pv.yaml](03-static-pv.yaml) sets `storageClassName: ""`. It also has a `claimRef` to `s13-volumes/student-pvc`, which reserves the PV for my claim so no other claim on the shared cluster can take it. [03-static-pvc.yaml](03-static-pvc.yaml) also sets `storageClassName: ""`.

```bash
$ kubectl apply -f 03-static-pv.yaml
persistentvolume/s13-student-pv created
$ kubectl get pv s13-student-pv
NAME             CAPACITY   ACCESS MODES   RECLAIM POLICY   STATUS      CLAIM                     STORAGECLASS   VOLUMEATTRIBUTESCLASS   REASON   AGE
s13-student-pv   1Gi        RWO            Retain           Available   s13-volumes/student-pvc                  <unset>                          0s
$ kubectl apply -f 03-static-pvc.yaml
persistentvolumeclaim/student-pvc created
$ kubectl get pv s13-student-pv; kubectl -n s13-volumes get pvc student-pvc
NAME             CAPACITY   ACCESS MODES   RECLAIM POLICY   STATUS   CLAIM                     STORAGECLASS   VOLUMEATTRIBUTESCLASS   REASON   AGE
s13-student-pv   1Gi        RWO            Retain           Bound    s13-volumes/student-pvc                  <unset>                          4s
NAME          STATUS   VOLUME           CAPACITY   ACCESS MODES   STORAGECLASS   VOLUMEATTRIBUTESCLASS   AGE
student-pvc   Bound    s13-student-pv   1Gi        RWO                           <unset>                 4s
$ kubectl apply -f 03-static-pod.yaml
pod/storage-demo created
$ kubectl -n s13-volumes wait --for=condition=Ready pod/storage-demo --timeout=120s
pod/storage-demo condition met
```

The claim asked for 500Mi but shows 1Gi: it gets the whole PV it is bound to.

Data survives Pod deletion:

```bash
$ kubectl -n s13-volumes exec storage-demo -- sh -c "echo Kubernetes Storage > /data/message.txt; cat /data/message.txt"
Kubernetes Storage
$ kubectl -n s13-volumes delete pod storage-demo && kubectl apply -f 03-static-pod.yaml
pod "storage-demo" deleted from s13-volumes namespace
pod/storage-demo created
$ kubectl -n s13-volumes wait --for=condition=Ready pod/storage-demo --timeout=120s
pod/storage-demo condition met
$ kubectl -n s13-volumes exec storage-demo -- cat /data/message.txt
Kubernetes Storage
$ kubectl describe pv s13-student-pv | grep -E "^(Name|Claim|Reclaim Policy|Status|Access Modes|Capacity)|Type:|Path:"
Name:            s13-student-pv
Status:          Bound
Claim:           s13-volumes/student-pvc
Reclaim Policy:  Retain
Access Modes:    RWO
Capacity:        1Gi
    Type:          HostPath (bare host directory volume)
    Path:          /tmp/s13-student-data
    HostPathType:  DirectoryOrCreate
```

`Retain` keeps the data even after the claim is deleted:

```bash
$ kubectl delete -f 03-static-pod.yaml -f 03-static-pvc.yaml
pod "storage-demo" deleted from s13-volumes namespace
persistentvolumeclaim "student-pvc" deleted from s13-volumes namespace
$ kubectl get pv s13-student-pv
NAME             CAPACITY   ACCESS MODES   RECLAIM POLICY   STATUS     CLAIM                     STORAGECLASS   VOLUMEATTRIBUTESCLASS   REASON   AGE
s13-student-pv   1Gi        RWO            Retain           Released   s13-volumes/student-pvc                  <unset>                          21s
$ minikube ssh -- cat /tmp/s13-student-data/message.txt
Kubernetes Storage
```

A `Released` PV is not given to a new claim automatically. An admin has to look at the data, clean it up, and then delete the PV or reuse it.

## 4. StorageClass and dynamic provisioning

A **StorageClass** describes a type of storage (which provisioner, parameters, reclaim policy, binding mode). With **dynamic provisioning**, a PVC that names a class (or uses the default class) makes the class's provisioner create a matching PV automatically, so no admin has to create PVs by hand. On minikube the default class is `standard`, backed by the `k8s.io/minikube-hostpath` provisioner, which creates directories under `/tmp/hostpath-provisioner/` on the node.

```bash
$ kubectl get storageclass
NAME                 PROVISIONER                RECLAIMPOLICY   VOLUMEBINDINGMODE   ALLOWVOLUMEEXPANSION   AGE
standard (default)   k8s.io/minikube-hostpath   Delete          Immediate           false                  37m
$ kubectl describe storageclass standard | grep -E "^(Name|IsDefaultClass|Provisioner|ReclaimPolicy|VolumeBindingMode)"
Name:            standard
IsDefaultClass:  Yes
Provisioner:           k8s.io/minikube-hostpath
ReclaimPolicy:         Delete
VolumeBindingMode:     Immediate
$ kubectl apply -f 04-dynamic-pvc.yaml
persistentvolumeclaim/dynamic-pvc created
pod/dynamic-demo created
$ kubectl -n s13-volumes wait --for=condition=Ready pod/dynamic-demo --timeout=120s
pod/dynamic-demo condition met
$ kubectl -n s13-volumes get pvc dynamic-pvc
NAME          STATUS   VOLUME                                     CAPACITY   ACCESS MODES   STORAGECLASS   VOLUMEATTRIBUTESCLASS   AGE
dynamic-pvc   Bound    pvc-469c6016-7ad2-408e-8d8b-4b0fb8ef11be   500Mi      RWO            standard       <unset>                 1s
$ kubectl get pv $(kubectl -n s13-volumes get pvc dynamic-pvc -o jsonpath='{.spec.volumeName}')
NAME                                       CAPACITY   ACCESS MODES   RECLAIM POLICY   STATUS   CLAIM                     STORAGECLASS   VOLUMEATTRIBUTESCLASS   REASON   AGE
pvc-469c6016-7ad2-408e-8d8b-4b0fb8ef11be   500Mi      RWO            Delete           Bound    s13-volumes/dynamic-pvc   standard       <unset>                          1s
$ kubectl describe pv $(kubectl -n s13-volumes get pvc dynamic-pvc -o jsonpath='{.spec.volumeName}') | grep -E 'provisioned-by|Path:'
                 pv.kubernetes.io/provisioned-by: k8s.io/minikube-hostpath
    Path:          /tmp/hostpath-provisioner/s13-volumes/dynamic-pvc
$ kubectl -n s13-volumes exec dynamic-demo -- cat /data/hello.txt
written to a dynamically provisioned volume
$ minikube ssh -- cat /tmp/hostpath-provisioner/s13-volumes/dynamic-pvc/hello.txt
written to a dynamically provisioned volume
```

I created only the PVC. The PV `pvc-469c...` was created within a second, with exactly the requested 500Mi and the class's `Delete` policy. Deleting the claim removes the PV and the data:

```bash
$ kubectl delete -f 04-dynamic-pvc.yaml
persistentvolumeclaim "dynamic-pvc" deleted from s13-volumes namespace
pod "dynamic-demo" deleted from s13-volumes namespace
$ kubectl get pv | grep -c s13-volumes/dynamic-pvc || true
0
$ minikube ssh -- ls /tmp/hostpath-provisioner/s13-volumes/
```

### My own StorageClass with WaitForFirstConsumer

[05-storageclass-wffc.yaml](05-storageclass-wffc.yaml) creates `s13-wffc`: same provisioner, but `volumeBindingMode: WaitForFirstConsumer`. The volume is only created after a Pod using the claim has been scheduled, so on a multi-zone cloud cluster the disk ends up in the same zone as the Pod. Before any Pod uses it, the claim waits:

```bash
$ kubectl apply -f 05-storageclass-wffc.yaml
storageclass.storage.k8s.io/s13-wffc created
persistentvolumeclaim/wffc-pvc created
$ kubectl get storageclass s13-wffc
NAME       PROVISIONER                RECLAIMPOLICY   VOLUMEBINDINGMODE      ALLOWVOLUMEEXPANSION   AGE
s13-wffc   k8s.io/minikube-hostpath   Delete          WaitForFirstConsumer   false                  8s
$ kubectl -n s13-volumes get pvc wffc-pvc
NAME       STATUS    VOLUME   CAPACITY   ACCESS MODES   STORAGECLASS   VOLUMEATTRIBUTESCLASS   AGE
wffc-pvc   Pending                                      s13-wffc       <unset>                 8s
$ kubectl -n s13-volumes describe pvc wffc-pvc | sed -n "/^Events/,\$p"
Events:
  Type    Reason                Age              From                         Message
  ----    ------                ----             ----                         -------
  Normal  WaitForFirstConsumer  8s (x2 over 8s)  persistentvolume-controller  waiting for first consumer to be created before binding
$ kubectl apply -f 05-wffc-pod.yaml
pod/wffc-demo created
$ kubectl -n s13-volumes wait --for=condition=Ready pod/wffc-demo --timeout=120s
error: timed out waiting for the condition on pods/wffc-demo
```

This did not work at first. Investigation:

```bash
$ kubectl -n s13-volumes get pod wffc-demo
NAME        READY   STATUS    RESTARTS   AGE
wffc-demo   0/1     Pending   0          2m58s
$ kubectl -n s13-volumes describe pvc wffc-pvc | grep -E "selected-node|ProvisioningFailed"
               volume.kubernetes.io/selected-node: minikube
  Warning  ProvisioningFailed    73s (x4 over 2m58s)  k8s.io/minikube-hostpath_minikube_7ea85d63-39ab-4d87-8315-0e7b0631c27c  failed to get target node: nodes "minikube" is forbidden: User "system:serviceaccount:kube-system:storage-provisioner" cannot get resource "nodes" in API group "" at the cluster scope
$ kubectl auth can-i get nodes --as=system:serviceaccount:kube-system:storage-provisioner
Warning: resource 'nodes' is not namespace scoped

no
```

The scheduler did its part: it picked a node and wrote it into the claim (`selected-node: minikube`). The minikube provisioner then tries to read that Node object, but its ServiceAccount has no permission to `get nodes`, so it never creates the volume. With the default `Immediate` mode this lookup does not happen, which is why `standard` works. [05-provisioner-rbac-fix.yaml](05-provisioner-rbac-fix.yaml) grants only that one read-only verb (prefixed `s13-`, deleted afterwards):

```bash
$ kubectl apply -f 05-provisioner-rbac-fix.yaml
clusterrole.rbac.authorization.k8s.io/s13-storage-provisioner-read-nodes created
clusterrolebinding.rbac.authorization.k8s.io/s13-storage-provisioner-read-nodes created
$ kubectl auth can-i get nodes --as=system:serviceaccount:kube-system:storage-provisioner
Warning: resource 'nodes' is not namespace scoped

yes
$ kubectl -n s13-volumes wait --for=condition=Ready pod/wffc-demo --timeout=120s
pod/wffc-demo condition met
$ kubectl -n s13-volumes get pvc wffc-pvc; kubectl -n s13-volumes get pod wffc-demo
NAME       STATUS   VOLUME                                     CAPACITY   ACCESS MODES   STORAGECLASS   VOLUMEATTRIBUTESCLASS   AGE
wffc-pvc   Bound    pvc-06c78a73-954d-40e5-bfda-28b68526a9cf   100Mi      RWO            s13-wffc       <unset>                 3m56s
NAME        READY   STATUS    RESTARTS   AGE
wffc-demo   1/1     Running   0          3m48s
$ kubectl -n s13-volumes logs wffc-demo
Filesystem                Size      Used Available Use% Mounted on
/dev/vdb1                58.8G     31.9G     23.8G  57% /data
$ kubectl -n s13-volumes describe pvc wffc-pvc | sed -n "/^Events/,\$p" | grep -E "Events|Type|----|ProvisioningSucceeded"
Events:
  Type     Reason                 Age                    From                                                                    Message
  ----     ------                 ----                   ----                                                                    -------
  Normal   ProvisioningSucceeded  3s                     k8s.io/minikube-hostpath_minikube_7ea85d63-39ab-4d87-8315-0e7b0631c27c  Successfully provisioned volume pvc-06c78a73-954d-40e5-bfda-28b68526a9cf
```

With the permission in place, the provisioner created the volume on the next retry and the Pod started. The `df` output also shows a limit of hostPath-based volumes: the 100Mi size is not enforced, and the Pod sees the whole node disk. Real CSI drivers (EBS, PD, Azure Disk) create a disk of the requested size.

### Cleanup of the cluster-scoped objects

```bash
$ kubectl delete -f 05-wffc-pod.yaml -f 05-storageclass-wffc.yaml -f 05-provisioner-rbac-fix.yaml
pod "wffc-demo" deleted from s13-volumes namespace
storageclass.storage.k8s.io "s13-wffc" deleted
persistentvolumeclaim "wffc-pvc" deleted from s13-volumes namespace
clusterrole.rbac.authorization.k8s.io "s13-storage-provisioner-read-nodes" deleted
clusterrolebinding.rbac.authorization.k8s.io "s13-storage-provisioner-read-nodes" deleted
$ kubectl delete -f 03-static-pv.yaml
persistentvolume "s13-student-pv" deleted
$ minikube ssh -- sudo rm -rf /tmp/s13-hostpath-data /tmp/s13-student-data && echo removed node dirs
removed node dirs
$ kubectl get pv,storageclass | grep -E "NAME|s13" 
NAME                                                        CAPACITY   ACCESS MODES   RECLAIM POLICY   STATUS   CLAIM                                        STORAGECLASS   VOLUMEATTRIBUTESCLASS   REASON   AGE
NAME                                             PROVISIONER                RECLAIMPOLICY   VOLUMEBINDINGMODE   ALLOWVOLUMEEXPANSION   AGE
```

Only the header lines are left, so no `s13-` PV or StorageClass remains. After that I deleted the `s13-volumes` namespace.

## Summary

| Type | Lifetime of the data | Scope | Typical use |
| :--- | :--- | :--- | :--- |
| emptyDir | the Pod (survives container restarts) | one Pod, all its containers | scratch space, caches, sidecar file sharing |
| hostPath | the node | one node | node agents, single-node labs |
| PV + PVC (static) | independent of Pods, `Retain`/`Delete` decides | cluster (PV) / namespace (PVC) | existing disks or NFS shares an admin hands out |
| StorageClass + PVC (dynamic) | independent of Pods, by default deleted with the claim | provisioner creates PVs on demand | normal choice for stateful apps on cloud clusters |
