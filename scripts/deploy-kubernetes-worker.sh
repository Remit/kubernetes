#!/bin/sh
# The script joins the worker node to the existing Kubernetes cluster
# Parameters:
# 1 - address of master node
# 2 - generated token
# 3 - cert hash

if [[ ! -z "$1" ]]
  then
    echo "Address of master node is not specified"
    exit 1
fi

if [[ ! -z "$2" ]]
  then
    echo "Generated token not specified"
    exit 1
fi

if [[ ! -z "$3" ]]
  then
    echo "CA certificate hash not specified"
    exit 1
fi

# If CNI configuration does not work - check https://docs.projectcalico.org/v1.5/getting-started/kubernetes/installation/
sudo rm -rf /var/lib/cni/
sudo kubeadm join $1 --token $2 --discovery-token-ca-cert-hash $3
sudo kubectl apply -f https://docs.projectcalico.org/v3.8/manifests/calico.yaml
# In case of issues with Calico - https://github.com/projectcalico/calico/issues/2699
# Here we enable some ports to be used when exposing pod ports via services for convenience
sudo cat /etc/kubernetes/manifests/kube-apiserver.yaml | sed 's/- --secure-port=6443/- --secure-port=6443\n    - --service-node-port-range=8000-60000/' > kube-apiserver.yaml
sudo cp kube-apiserver.yaml /etc/kubernetes/manifests/kube-apiserver.yaml
rm -f kube-apiserver.yaml
