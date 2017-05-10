# On-Premise Kubernetes Federation with CoreDNS as DNS provider

[![asciicast](https://asciinema.org/a/14.png)](https://asciinema.org/a/cy6jjezak5fn8f3l632boilmj)


Here, we'll setup a Kubernetes federation, fully on on-premise machines (bare metal, VMs...), i.e. without being attached to any cloud provider.

If you don't know the basics of Kubernetes Federation, you can take a look at this [doc](https://github.com/kubernetes/community/blob/master/contributors/design-proposals/federation.md).

The information on how Setting up Cluster Federation with Kubefed was found in this [tutorial](https://kubernetes.io/docs/tutorials/federation/set-up-cluster-federation-kubefed/).

## Before we start

For this tutorial, we have two Kubernetes clusters, created using kubeadm. You can find how to create them [here](https://kubernetes.io/docs/getting-started-guides/kubeadm/). Make sure that the machines running each cluster can communicate with each other.
If you're running in a cloud environment, you might need to open some firewall ports.

Our main objective here is to guide you through the whole deploy of Federation control plane API running on Cluster 1 and join the Clusters 1 and 2 to that Federation.

|   Cluster 1                                |  Cluster 2                                 |
|:------------------------------------------:|:------------------------------------------:|
| **master-c1** (hypothetical IP: 1.1.1.1)   | **master-c2** (hypothetical IP: 2.2.2.2)   |
| worker-c1-1                                | worker-c2-1                                |
| worker-c1-2                                | worker-c2-2                                |
| worker-c1-*N*                              | worker-c2-*N*                              |

### Get kubefed

* Download kubernetes client and install `kubectl` and `kubefed`.

```bash
# Linux
$ curl -LO https://storage.googleapis.com/kubernetes-release/release/$(curl -s https://storage.googleapis.com/kubernetes-release/release/stable.txt)/kubernetes-client-linux-amd64.tar.gz
$ tar -xzvf kubernetes-client-linux-amd64.tar.gz

# OS X
$ curl -LO https://storage.googleapis.com/kubernetes-release/release/$(curl -s https://storage.googleapis.com/kubernetes-release/release/stable.txt)/kubernetes-client-darwin-amd64.tar.gz
$ tar -xzvf kubernetes-client-darwin-amd64.tar.gz

# Windows
$ curl -LO https://storage.googleapis.com/kubernetes-release/release/$(curl -s https://storage.googleapis.com/kubernetes-release/release/stable.txt)/kubernetes-client-windows-amd64.tar.gz
$ tar -xzvf kubernetes-client-windows-amd64.tar.gz
```

| Note: You can download it to other architectures than amd64 in the [release page](https://github.com/kubernetes/kubernetes/blob/master/CHANGELOG.md#client-binaries-1).

* Copy the extracted binaries to */usr/local/bin* path and set the executable permission to them.

```bash
$ cp kubernetes/client/bin/kubefed /usr/local/bin
$ chmod +x /usr/local/bin/kubefed
$ cp kubernetes/client/bin/kubectl /usr/local/bin
$ chmod +x /usr/local/bin/kubectl
```

### Deploying CoreDNS and etcd-operator

* For more detailed information about how to set up CoreDNS Provider, you can see [official docs](https://kubernetes.io/docs/tutorials/federation/set-up-coredns-provider-federation/).
* We use [**Helm**](https://github.com/kubernetes/helm) to deploy them, **install and initialize it**.
* If your Kubernetes version is 1.6 or higher, you should [configure rbac rules](https://github.com/coreos/etcd-operator/blob/master/doc/user/rbac.md), before you create the etcd-operator helm chart. A 'permissive binding' will be created to to supply this need:

```bash
$ kubectl create clusterrolebinding permissive-binding \
  --clusterrole=cluster-admin \
  --user=admin \
  --user=kubelet \
  --group=system:serviceaccounts
```

* Deploy the etcd-operator chart.

```bash
$ helm install --name etcd-operator stable/etcd-operator
$ helm upgrade --set cluster.enabled=true etcd-operator stable/etcd-operator
```

* Get the IP of etcd-cluster service and add to */etc/hosts* with a domain name (e.g. etcd-cluster.onprem).

```bash
$ kubectl get svc etcd-cluster
NAME           CLUSTER-IP      EXTERNAL-IP   PORT(S)    AGE
etcd-cluster   1.1.1.1         <none>        2379/TCP   5m

# Adding an entry in etc/hosts with its CLUSTER-IP
$ echo "1.1.1.1   etcd-cluster.onprem" >> /etc/hosts
```

* Create a file called **coredns-chart-config.yaml** with the command below:

```bash
$ cat <<EOF > coredns-chart-config.yaml
isClusterService: false
serviceType: "NodePort"
middleware:
  kubernetes:
    enabled: false
  etcd:
    enabled: true
    zones:
    - "example.com."
    endpoint: "http://etcd-cluster.onprem:2379"
EOF
```

* Then, deploy the CoreDNS chart passing the config file as a parameter. More information [here](https://github.com/kubernetes/charts/tree/master/stable/coredns).

```bash
$ helm install --name=coredns -f=coredns-chart-config.yaml stable/coredns
```

### Initilizing the Federation Control Plane

* For now, we can view the default kubeconfig file with one cluster and one context, whose values are by defaul in **admin.conf** file (/etc/kubernetes/admin.conf).

```yaml
$ kubectl config view
apiVersion: v1
clusters:
- cluster:
    certificate-authority-data: REDACTED
    server: https://1.1.1.1:6443
  name: kubernetes
contexts:
- context:
    cluster: kubernetes
    user: kubernetes-admin
  name: kubernetes-admin@kubernetes
current-context: kubernetes-admin@kubernetes
kind: Config
preferences: {}
users:
- name: kubernetes-admin
  user:
    client-certificate-data: REDACTED
    client-key-data: REDACTED
```

* Create **coredns-provider.conf** file with the following content:

```bash
$ cat <<EOF > coredns-provider.conf
[Global]
etcd-endpoints = http://etcd-cluster.onprem:2379
zones = example.com.
EOF
```

* Now, initialize the Federation Control Plane (Use `kubefed init --help` for more information about the parameters)

```bash
$ kubefed init federation-control-pane \
    --host-cluster-context=kubernetes-admin@kubernetes \
    --dns-provider="coredns" \
    --dns-zone-name="example.com." \
    --api-server-advertise-address=1.1.1.1 \
    --api-server-service-type='NodePort' \
    --dns-provider-config="coredns-provider.conf" \
    --etcd-persistent-storage=false
```

* If the initialization was successfull, the kubeconfig should have been updated, with a new context called `federation-control-plane` created

```yaml
$ kubectl config view

apiVersion: v1
clusters:
- cluster:
    certificate-authority-data: REDACTED
    server: https://1.1.1.1:31806
  name: federation-control-pane
...
contexts:
- context:
    cluster: federation-control-pane
    user: federation-control-pane
  name: federation-control-pane
...
kind: Config
preferences: {}
users:
- name: federation-control-pane
  user:
    client-certificate-data: REDACTED
    client-key-data: REDACTED
...
```

* At this point, we have edited the **admin.conf** file to improve readability. We have manually renamed the contexts, clusters and users. You can do this by editing the file or ideally using the `kubectl config` commands such as `set-context` and `set-cluster`.

```yaml
$ kubectl config view

apiVersion: v1
clusters:
- cluster:
    certificate-authority-data: REDACTED
    server: https://1.1.1.1:6443
  name: cluster-1
- cluster:
    certificate-authority-data: REDACTED
    server: https://1.1.1.1:31806
  name: fed-control-plane
contexts:
- context:
    cluster: cluster-1
    user: c1-admin
  name: c1-admin@cluster-1
- context:
    cluster: fed-control-plane
    user: fed-admin
  name: fed-admin@fed-control-plane
current-context: c1-admin@cluster-1
kind: Config
preferences: {}
users:
- name: c1-admin
  user:
    client-certificate-data: REDACTED
    client-key-data: REDACTED
- name: fed-admin
  user:
    client-certificate-data: REDACTED
    client-key-data: REDACTED
```

```bash
# Getting the new, renamed contexts
$ kubectl config get-contexts
CURRENT   NAME                          CLUSTER             AUTHINFO    NAMESPACE
*         c1-admin@cluster-1            cluster-1           c1-admin
          fed-admin@fed-control-plane   fed-control-plane   fed-admin
```

* Change the current context to federation.

```bash
$ kubectl config use-context fed-admin@fed-control-plane
Switched to context "fed-admin@fed-control-plane".
```

### Joining the fist service cluster

At this point, you have a Federation running, with control plane and api-server deployed. However, it doesn't have any underlying cluster to hold resources like pods. To have so, we need to join clusters to the federation. The first cluster we are going to join is the same cluster the federation-control-plane is running. This means that, in different contexts, this cluster will hold the federation resources, and also work as a federation service provider per se.

* Join the Cluster 1 to federation, using its information in the kubeconfig file

```bash
$ kubefed join cluster-1 \
    --host-cluster-context=c1-admin@cluster-1 \
    --cluster-context=c1-admin@cluster-1
cluster "cluster-1" created

# Verify if it was added and wait for it to have status READY
$ kubectl get clusters
NAME        STATUS    AGE
cluster-1   Ready     15s
```

### Joining another cluster

Now, you need to accesss the auth information of Cluster 2 from its kubeconfig/admin.conf (on `master-c2`) file. Edit your main kubeconfig file (**admin.conf** on `master-c1`) to receive the new entries. You must add a cluster, context and a user entry, according to `master-c2` specs and credentials. Your configuration should look like the following:

```yaml
$ kubectl config view

apiVersion: v1
clusters:
- cluster:
    certificate-authority-data: REDACTED
    server: https://1.1.1.1:6443
  name: cluster-1
- cluster:
    certificate-authority-data: REDACTED
    server: https://2.2.2.2:6443
  name: cluster-2
- cluster:
    certificate-authority-data: REDACTED
    server: https://1.1.1.1:31806
  name: fed-control-plane
contexts:
- context:
    cluster: cluster-1
    user: c1-admin
  name: c1-admin@cluster-1
- context:
    cluster: cluster-2
    user: c2-admin
  name: c2-admin@cluster-2
- context:
    cluster: fed-control-plane
    user: fed-admin
  name: fed-admin@fed-control-plane
current-context: fed-admin@fed-control-plane
kind: Config
preferences: {}
users:
- name: c1-admin
  user:
    client-certificate-data: REDACTED
    client-key-data: REDACTED
- name: c2-admin
  user:
    client-certificate-data: REDACTED
    client-key-data: REDACTED
- name: fed-admin
  user:
    client-certificate-data: REDACTED
    client-key-data: REDACTED
```

* Now, join the second cluster to the federation

```bash
$ kubefed join cluster-2 \
    --host-cluster-context=c1-admin@cluster-1 \
    --cluster-context=c1-admin@cluster-2
cluster "cluster-2" created

# Again verify it, and wait for it to be READY
$ kubectl get clusters
NAME        STATUS    AGE
cluster-1   Ready     5m
cluster-2   Ready     16s
```

If it was correctly added, you can now run things like a replicaset in the federation context and see how the replicas are being distributed among the underlying clusters, by swithing the contexts.


## Contact

Any questions or suggestions, contact me at artmr@lsd.ufcg.edu.br


Hello, I'm trying  to join a gke cluster on my on-premise federation control plane, however, some validations fail:

scenario:
```
$ kubectl config get-clusters
NAME
onprem-c1
federation-control-pane
gke_k8s-testing-166514_us-central1-a_gke-1
root@art-z1-master:~# kubectl config get-contexts
CURRENT   NAME                                         CLUSTER                                      AUTHINFO                                     
*         federation-control-pane                      federation-control-pane                      federation-control-pane                      
          gke_k8s-testing-166514_us-central1-a_gke-1   gke_k8s-testing-166514_us-central1-a_gke-1   gke_k8s-testing-166514_us-central1-a_gke-1   
          onprem-c1                                    onprem-c1                                    onprem-c1       
```



https://github.com/kubernetes/kubernetes/blob/master/staging/src/k8s.io/apimachinery/pkg/util/validation/validation.go#L131

