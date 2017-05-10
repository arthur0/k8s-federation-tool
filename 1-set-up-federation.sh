#!/usr/bin/env bash
source util.sh

# KUBECTL_PARAMS="--context=foo"

# TODO: Try/adapt to different namespaces
NAMESPACE=${NAMESPACE:-"default"}
KUBECTL="kubectl ${KUBECTL_PARAMS} --namespace=\"${NAMESPACE}\""
ZONES=${ZONES:-"example.com."}
SERVICE_TYPE=${SERVICE_TYPE:-"NodePort"}
KUBECONFIG=${KUBE_CONFIG:-"/root/admin.conf"}
MASTER_IP=`kubectl get nodes --selector=node-role.kubernetes.io/master  -o jsonpath={.items[0].status.addresses[0].address}`
HOST_CONTEXT=`kubectl config  get-contexts | awk 'NR==2{print $2}'`


# TODO: Allow file call/ Show permissive-binding creating message
eval "${KUBECTL} create clusterrolebinding permissive-binding \
    --clusterrole=cluster-admin \
    --user=admin \
    --user=kubelet \
    --group=system:serviceaccounts"

eval "helm init --upgrade"

#  Wait for tiller pod to be ready.
tiller_available=""
loading="Loading Tiller "
while [ -z "${tiller_available}" ]  # while test "tiller_available" is empty
do
  echo -ne "${loading} \r"
  tiller_available=`${KUBECTL} get deploy tiller-deploy -n=kube-system -o jsonpath={.status.availableReplicas} 2> /dev/null`
  loading+="#"
  sleep 1
done
clean_screen
print_green "Tiller is running!"

eval "helm install --name etcd-operator stable/etcd-operator"
eval "helm upgrade --set cluster.enabled=true etcd-operator stable/etcd-operator"

# Wait for etcd-cluster service to be ready.
cluster_IP=""
loading="Loading etcd-cluster service "
while [  -z "${cluster_IP}" ]     # while test "cluster_IP" is empty
do
  echo -ne "${loading} \r"
  cluster_IP=`kubectl get svc etcd-cluster -o jsonpath={.spec.clusterIP} 2> /dev/null`
  loading+="#"
  sleep 1
done
clean_screen
print_green "etcd-cluster service is running!"

# Deploy CoreDNS
ENDPOINT="http://etcd-cluster.${NAMESPACE}:2379"
# TODO: Allow file call
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
    endpoint: ${ENDPOINT}
EOF
eval "helm install --name=coredns -f=coredns-chart-config.yaml stable/coredns"

# TODO: Allow file call
cat <<EOF > coredns-provider.conf
[Global]
etcd-endpoints = ${ENDPOINT}
zones = ${ZONES}
EOF

# TODO: Allow and create etcd persistent storage
eval "kubefed init federation \
    --host-cluster-context=${HOST_CONTEXT} \
    --api-server-service-type="${SERVICE_TYPE}" \
    --api-server-advertise-address="${MASTER_IP}" \
    --apiserver-enable-token-auth="true" \
    --dns-provider="coredns" \
    --dns-zone-name="${ZONES}" \
    --dns-provider-config="coredns-provider.conf" \
    --etcd-persistent-storage="false"\
    --kubeconfig="${KUBECONFIG}""

print_green "Federation Control Plane was deployed!"

eval "${KUBECTL} config use-context federation"
eval "${KUBECTL} config get-contexts"

