# On-Premise Kubernetes Federation with CoreDNS as DNS provider

Here, we'll setup a Kubernetes federation, fully on on-premise VMs. 

If you don't know the basics of Kubernetes Federation, you can take a look at this [doc](https://github.com/kubernetes/community/blob/master/contributors/design-proposals/federation.md).

The information how Setting up Cluster Federation with Kubefed was found in this [tutorial](https://kubernetes.io/docs/tutorials/federation/set-up-cluster-federation-kubefed/).  

## Before we start

For this tutorial, we have two Kubernetes clusters, created using kubeadm. You can find how to create them [here](https://kubernetes.io/docs/getting-started-guides/kubeadm/).

Our main objective is to guide you to deploy Federation control plane API running on Cluster 1 and join the Clusters 1 and 2 to the Federation.

|   Cluster 1                                |  Cluster 2                                 |  
|:------------------------------------------:|:------------------------------------------:|
| **master-c1** (hypothetical IP: 1.1.1.1)   | **master-c2** (hypothetical IP: 2.2.2.2)   |
| worker-c1-1                                | worker-c2-1                                |
| worker-c1-2                                | worker-c2-2                                |
| worker-c1-*N*                              | worker-c2-*N*                              |


### Get kubefed

* Download kubernetes client.

```bash
# Linux
master-c1$ curl -LO https://storage.googleapis.com/kubernetes-release/release/$(curl -s https://storage.googleapis.com/kubernetes-release/release/stable.txt)/kubernetes-client-linux-amd64.tar.gz
master-c1$ tar -xzvf kubernetes-client-linux-amd64.tar.gz

# OS X
master-c1$ curl -LO https://storage.googleapis.com/kubernetes-release/release/$(curl -s https://storage.googleapis.com/kubernetes-release/release/stable.txt)/kubernetes-client-darwin-amd64.tar.gz
master-c1$ tar -xzvf kubernetes-client-darwin-amd64.tar.gz

# Windows
master-c1$ curl -LO https://storage.googleapis.com/kubernetes-release/release/$(curl -s https://storage.googleapis.com/kubernetes-release/release/stable.txt)/kubernetes-client-windows-amd64.tar.gz
master-c1$ tar -xzvf kubernetes-client-windows-amd64.tar.gz
```
 
 | Note: You can download different architectures of x64 in [release page](https://github.com/kubernetes/kubernetes/blob/master/CHANGELOG.md#client-binaries-1).
 
* Copy the extracted binaries to */usr/local/bin* path and set the executable permission to them.
```bash
master-c1$ cp kubernetes/client/bin/kubefed /usr/local/bin
master-c1$ chmod +x /usr/local/bin/kubefed
master-c1$ cp kubernetes/client/bin/kubectl /usr/local/bin
master-c1$ chmod +x /usr/local/bin/kubectl
```
### Deploying CoreDNS and etcd-operator
* For more detailed information about how to set up CoreDNS Provider, you can see [official docs](https://kubernetes.io/docs/tutorials/federation/set-up-coredns-provider-federation/).
* We use [**Helm**](https://github.com/kubernetes/helm) to deploy them, **install and initialize it**.
* If your Kubernetes version is 1.6 or higher, you should [configure rbac rules](https://github.com/coreos/etcd-operator/blob/master/doc/user/rbac.md), before you create the etcd-operator helm chart. A 'permissive binding' will be created to to supply this need:

```bash
master-c1$ kubectl create clusterrolebinding permissive-binding \
  --clusterrole=cluster-admin \
  --user=admin \
  --user=kubelet \
  --group=system:serviceaccounts
```
* Deploy the etcd-operator chart.

```bash
master-c1$ helm install --name etcd-operator stable/etcd-operator
master-c1$ helm upgrade --set cluster.enabled=true etcd-operator stable/etcd-operator
```

* Get the IP of etcd-cluster service and add to */etc/hosts* with a domain name (e.g. etcd-cluster.onprem).
```bash
master-c1$ kubectl get svc etcd-cluster
NAME           CLUSTER-IP      EXTERNAL-IP   PORT(S)    AGE
etcd-cluster   1.1.1.1         <none>        2379/TCP   5m
master-c1$ echo "1.1.1.1   etcd-cluster.onprem" >> /etc/hosts
```
* Write **coredns-chart-config.yaml** file and deploy the CoreDNS chart passing the config file as a parameter. More information [here](https://github.com/kubernetes/charts/tree/master/stable/coredns).
 
```yaml
# coredns-chart-config.yaml
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
```

```bash
master-c1$ helm install --name=coredns -f=coredns-chart-config.yaml stable/coredns
```

### Initilizing the Federation Control Plane

* For now, we can view the default KubeConfig with one cluster and one context, whose values can be changed editing the **admin.conf** (default /etc/kubernetes/admin.conf ).
```yaml
master-c1$ kubectl config view
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

* Writte **coredns-provider.conf** with the format bellow
```
[Global]
etcd-endpoints = http://etcd-cluster.onprem:2379
zones = example.com.
```

* Initialize the Federation Control Plane. (Use `kubefed init --help` for more information about the parameters) 
```bash
master-c1$ kubefed init federation-control-pane \
    --host-cluster-context=kubernetes-admin@kubernetes \
    --dns-provider="coredns" \
    --dns-zone-name="example.com." \
    --api-server-advertise-address=1.1.1.1 \
    --api-server-service-type='NodePort' \
    --dns-provider-config="coredns-provider.conf" \
    --etcd-persistent-storage=false 
```

* The kubeConfig should be updated
```yaml
master-c1$ kubectl config view
apiVersion: v1
clusters:
- cluster:
    certificate-authority-data: REDACTED
    server: https://1.1.1.1:31806
  name: federation-control-pane
- cluster:
    certificate-authority-data: REDACTED
    server: https://1.1.1.1:6443
  name: kubernetes
contexts:
- context:
    cluster: federation-control-pane
    user: federation-control-pane
  name: federation-control-pane
- context:
    cluster: kubernetes
    user: kubernetes-admin
  name: kubernetes-admin@kubernetes
current-context: kubernetes-admin@kubernetes
kind: Config
preferences: {}
users:
- name: federation-control-pane
  user:
    client-certificate-data: REDACTED
    client-key-data: REDACTED
- name: kubernetes-admin
  user:
    client-certificate-data: REDACTED
    client-key-data: REDACTED
```

* The **admin.conf** file was edited to improve readability
```yaml
master-c1$ kubectl config view
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
master-c1$ kubectl config get-contexts
CURRENT   NAME                          CLUSTER             AUTHINFO    NAMESPACE
*         c1-admin@cluster-1            cluster-1           c1-admin    
          fed-admin@fed-control-plane   fed-control-plane   fed-admin   
```

* Change the current context to federation.
```bash
master-c1$ kubectl config use-context fed-admin@fed-control-plane
Switched to context "fed-admin@fed-control-plane".
```

* Join the Cluster 1 to federation 
```bash
master-c1$ kubefed join cluster-1 \
    --host-cluster-context=c1-admin@cluster-1 \
    --cluster-context=c1-admin@cluster-1
cluster "cluster-1" created
master-c1$ kubectl get clusters
NAME        STATUS    AGE
cluster-1   Ready     15s
```

* You can access auth information of Cluster 2 from **admin.conf** (on master-c2) file. Edit your **admin.conf** (on master-c1) to receive the new entries, so that your configuration looks like the following:
```yaml
master-c1$ kubectl config view
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
 
* Join the Cluster 2 federation 
```bash
master-c1$ kubefed join cluster-2 \
    --host-cluster-context=c1-admin@cluster-1 \
    --cluster-context=c1-admin@cluster-2
cluster "cluster-2" created
master-c1$ kubectl get clusters
NAME        STATUS    AGE
cluster-1   Ready     5m
cluster-2   Ready     16s
```

* Any question or suggestion, contact me artmr@lsd.ufcg.edu.br

