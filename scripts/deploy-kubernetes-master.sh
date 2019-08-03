#!/bin/sh
# The script:
# - makes the final preparation before starting the master
# - starts the master and CNI
# Arguments:
# 1 - cpu manager policy type {static, none}, e.g. static
# 2 - cpu shares reserved for kube-system pods, e.g. 300m
# 3 - memory shares reserved for kube-system pods, e.g. 300Mi
# 4 - ephemeralstorage reserved for kube-system pods, e.g. 1Gi

cpupolicy="static"
kuberescpu="300m"
kuberesmem="300Mi"
kubereseph="1Gi"

if [ ! -z "$1" ]
  then
    cpupolicy=$1
fi

if [ ! -z "$2" ]
  then
    kuberescpu=$2
fi

if [ ! -z "$3" ]
  then
    kuberesmem=$3
fi

if [ ! -z "$4" ]
  then
    kubereseph=$4
fi

hostname=$(cat /etc/hostname)

if [ hostname != "sparkone" ]; then
  echo "WARNING: you are starting master node not on SPARKONE machine! In order to isolate performance, it is recommended to deploy master and worker nodes on separate machines"
fi

sudo systemctl enable kubelet
sudo mkdir -p /etc/sysconfig/kubelet
sudo echo "KUBELET_EXTRA_ARGS=--cpu-manager-policy=$(cpupolicy) --v=4 --kube-reserved=cpu=$(kuberescpu),memory=$(kuberesmem),ephemeral-storage=$(kubereseph)" >> /etc/sysconfig/kubelet

sudo kubeadm init
sudo kubectl --kubeconfig /etc/kubernetes/admin.conf apply -f https://docs.projectcalico.org/v3.8/manifests/calico.yaml
# Here we enable some ports to be used when exposing pod ports via services for convenience
sudo cat /etc/kubernetes/manifests/kube-apiserver.yaml | sed 's/- --secure-port=6443/- --secure-port=6443\n    - --service-node-port-range=100-30000/' | sudo tee /etc/kubernetes/manifests/kube-apiserver.yaml
echo "Now you can use the output of the of kubeadm init of form kubeadm join... to join node to the cluster"
