#!/usr/bin/env bash
source ./util.sh

# TODO: Get context name
kubectl config use-context kubernetes-admin@kubernetes
helm delete --purge etcd-operator
helm delete --purge coredns
helm reset
kubectl delete clusterrolebinding permissive-binding
kubectl config delete-context federation-control-pane
kubectl config delete-cluster federation-control-pane
kubectl delete ns federation-system
print_green "Done!"