#!/bin/sh
# The script:
# - makes the final preparation before starting the master
# - starts the master and CNI
# Arguments:
# 1 - cpu manager policy type {static, none}, e.g. static
# 2 - cpu shares reserved for kube-system pods, e.g. 300m
# 3 - memory shares reserved for kube-system pods, e.g. 300Mi
# 4 - ephemeralstorage reserved for kube-system pods, e.g. 1Gi

initaddress="."
cpupolicy="static"
kuberescpu="1"
kuberesmem="2Gi"
kubereseph="1Gi"

if [ -z "$1" ]
  then
    echo "Advertised address/CIDR not specified, e.g. 192.168.10.60"
    exit 1
  else
    initaddress=$1
fi

if [ ! -z "$2" ]
  then
    cpupolicy=$2
fi

if [ ! -z "$3" ]
  then
    kuberescpu=$3
fi

if [ ! -z "$4" ]
  then
    kuberesmem=$4
fi

if [ ! -z "$5" ]
  then
    kubereseph=$5
fi

hostname=$(cat /etc/hostname)

sudo systemctl enable kubelet
sudo mkdir -p /etc/sysconfig/
sudo touch /etc/sysconfig/kubelet
sudo echo "KUBELET_EXTRA_ARGS=--cpu-manager-policy=$cpupolicy --v=4 --kube-reserved=cpu=$kuberescpu,memory=$kuberesmem,ephemeral-storage=$kubereseph" | sudo tee /etc/sysconfig/kubelet > /dev/null

# To avoid troubles with Calico
sudo rm -rf /var/lib/cni/

sudo kubeadm init --apiserver-advertise-address $initaddress --pod-network-cidr $initaddress/24 --kubernetes-version 1.15.6
sudo kubectl --kubeconfig /etc/kubernetes/admin.conf apply -f https://docs.projectcalico.org/v3.8/manifests/calico.yaml
# In case of issues with Calico - https://github.com/projectcalico/calico/issues/2699
# Here we enable some ports to be used when exposing pod ports via services for convenience
sudo cat /etc/kubernetes/manifests/kube-apiserver.yaml | sed 's/- --secure-port=6443/- --secure-port=6443\n    - --service-node-port-range=8000-60000/' > kube-apiserver.yaml
sudo cp kube-apiserver.yaml /etc/kubernetes/manifests/kube-apiserver.yaml
rm -f kube-apiserver.yaml
echo "Now you can use the output of the of kubeadm init of form kubeadm join... to join node to the cluster"
