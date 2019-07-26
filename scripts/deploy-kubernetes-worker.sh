#!/bin/sh
# The script joins the worker node to the existing Kubernetes cluster
# Parameters:
# 1 - address of master node
# 2 - generated token
# 3 - cert hash

if [ ! -z "$1" ]
  then
    echo "Address of master node is not specified"
    exit 1
fi

if [ ! -z "$2" ]
  then
    echo "Generated token not specified"
    exit 1
fi

if [ ! -z "$3" ]
  then
    echo "CA certificate hash not specified"
    exit 1
fi

# If CNI configuration does not work - check https://docs.projectcalico.org/v1.5/getting-started/kubernetes/installation/
sudo kubeadm join $1 --token $2 --discovery-token-ca-cert-hash $3
sudo kubectl apply -f https://docs.projectcalico.org/v3.8/manifests/calico.yaml
