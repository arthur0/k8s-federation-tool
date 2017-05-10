#!/usr/bin/env bash
source util.sh

if ! is_linux64 ; then
  print_red "[FAIL] This script works only for Linux x64 platforms."
  return 1
fi

install_kubefed(){
  echo "Installing kubefed..."
  curl -LO "https://storage.googleapis.com/kubernetes-release/release/$(curl -s https://storage.googleapis.com/kubernetes-release/release/stable.txt)/kubernetes-client-linux-amd64.tar.gz"
  tar -xzvf "kubernetes-client-linux-amd64.tar.gz"
  cp "kubernetes/client/bin/kubefed" "/usr/local/bin"
  chmod +x "/usr/local/bin/kubefed"
  cp "kubernetes/client/bin/kubectl" "/usr/local/bin"
  chmod +x "/usr/local/bin/kubectl"

  rm "kubernetes-client-linux-amd64.tar.gz"
  rm -r "kubernetes"

  print_green "Kubefed successfully installed!"
}

install_helm(){
  echo "Installing Helm..."
  curl "https://raw.githubusercontent.com/kubernetes/helm/master/scripts/get" >> "get_helm.sh" &&
  chmod 700 "get_helm.sh" &&
  ./get_helm.sh

  rm "get_helm.sh"

  print_green "Helm successfully installed!"
}

if ! type "kubefed" > /dev/null; then
  install_kubefed
fi

if ! type "helm" > /dev/null; then
  install_helm
fi

print_green "All dependencies are ready!"