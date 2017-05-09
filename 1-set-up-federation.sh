#!/usr/bin/env bash
source ./util.sh

# KUBECTL_PARAMS="--context=foo"

# TODO: Try/adapt to different namespaces
NAMESPACE=${NAMESPACE:-"default"}
KUBECTL="kubectl ${KUBECTL_PARAMS} --namespace=\"${NAMESPACE}\""
ENDPOINT=${ENDPOINT:-"http://etcd-cluster:2379"}
ZONES=${ZONES:-"example.com."}
SERVICE_TYPE=${SERVICE_TYPE:-"NodePort"}


# TODO: Allow file call
eval "${KUBECTL} create clusterrolebinding permissive-binding \
    --clusterrole=cluster-admin \
    --user=admin \
    --user=kubelet \
    --group=system:serviceaccounts"

eval "helm init --upgrade"
tiller_available=0
loading="loading "
while [ ${tiller_available} == 0 ]
do
  echo -ne "${loading} \r"
  tiller_available=`${KUBECTL} get deploy tiller-deploy -n=kube-system |  awk 'NR==2{print $5}'`
  loading+="#"
  sleep 1
done

eval "helm install --name etcd-operator stable/etcd-operator"
eval "helm upgrade --set cluster.enabled=true etcd-operator stable/etcd-operator"

# Wait for etcd-cluster service to be ready.
cluster_IP=""
loading="Loading "
while [  -z "${cluster_IP}" ]     # while test "$CLUSTER_IP" is empty
do
  echo -ne "${loading} \r"
  cluster_IP=`kubectl get svc | grep 'etcd-cluster' | awk 'NR==1{print $2}'`
  loading+="#"
  sleep 3
done
print_green "etcd-cluster service is running!"

echo "${cluster_IP}   ${ENDPOINT}" >> "/etc/hosts"


# CoreDNS Helm Chart values  TODO: Allow file call
cat <<EOF > coredns-chart-config.yaml
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

eval "helm install --name=coredns -f=coredns-chart-config.yaml stable/coredns"

# TODO: Allow file call
cat <<EOF > coredns-provider.conf
[Global]
etcd-endpoints = ${ENDPOINT}
zones = ${ZONES}
EOF

# TODO: Allow and create etcd persistent storage
eval "kubefed init federation-control-pane \
    --host-cluster-context=kubernetes-admin@kubernetes \
    --dns-provider=coredns \
    --dns-zone-name=${ZONES} \
    --api-server-advertise-address=${cluster_IP} \
    --api-server-service-type=${SERVICE_TYPE} \
    --dns-provider-config=coredns-provider.conf \
    --etcd-persistent-storage=false"

# TODO: Create Cleanup of files

print_green "Federation Control Plane was deployed!"

eval "${KUBECTL} config use-context federation-control-pane"
eval "${KUBECTL} config get-contexts"

