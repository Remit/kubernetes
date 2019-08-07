#!/bin/sh
# Script that deploys data-analytics benchmark from EPFL CloudSuite and starts it
# Should be run on Kubernetes master! Ensure correct host names.

MASTER_NODE=k8instance
WORKER_NODE=k8instance

# Tainting nodes to ensure that master and worker run on distinct nodes
# Note: for the sake of testing, they were assigned to be same. If they are the same,
# we assume that everything runs on the same node -> the master node should be untainted
if [ $MASTER_NODE = $WORKER_NODE ]; then
  sudo kubectl --kubeconfig /etc/kubernetes/admin.conf taint nodes --all node-role.kubernetes.io/master-
fi

sudo kubectl --kubeconfig /etc/kubernetes/admin.conf taint nodes $MASTER_NODE allowed=$MASTER_NODE:NoSchedule --overwrite
sudo kubectl --kubeconfig /etc/kubernetes/admin.conf taint nodes $WORKER_NODE allowed=$WORKER_NODE:NoSchedule --overwrite

# Deploying master and worked in Kubernetes
sudo kubectl --kubeconfig /etc/kubernetes/admin.conf apply -f benchmarks/cloudsuite/data-analytics/master-deployment.yaml
sudo kubectl --kubeconfig /etc/kubernetes/admin.conf apply -f benchmarks/cloudsuite/data-analytics/worker-deployment.yaml

# Deploying Kubernetes service to ensure external acces to the master in case it is needed (<name>.default.svc.cluster.local)
sudo kubectl --kubeconfig /etc/kubernetes/admin.conf apply -f benchmarks/cloudsuite/data-analytics/master-service.yaml

sleep 60
MASTER_CONTAINER_ID=$(docker ps | grep master_cloudsuite-data-analytics-master-deployment | cut -d' ' -f 1)

docker exec $MASTER_CONTAINER_ID benchmark
# Give a try to https://blog.hasura.io/getting-started-with-hdfs-on-kubernetes-a75325d4178c/ and report back to EPFL

# https://www.tutorialspoint.com/hadoop/hadoop_multi_node_cluster
# change /etc/hosts?
# change .../slaves? /masters?
#https://cloudnativelabs.github.io/post/2017-04-18-kubernetes-networking/
# To enter the container:
# docker exec -it $MASTER_CONTAINER_ID bin/bash


# https://docs.projectcalico.org/v3.8/getting-started/bare-metal/installation/container
# Calico network for container? to connect to calico for pods?
# https://kubernetes.io/docs/concepts/services-networking/network-policies/
# https://docs.projectcalico.org/v3.8/security/calico-network-policy

# install etcd:
# For reference https://computingforgeeks.com/how-to-install-etcd-on-ubuntu-18-04-ubuntu-16-04/

# install calicoctl:
# curl -O -L  https://github.com/projectcalico/calicoctl/releases/download/v3.8.1/calicoctl
# sudo cp calicoctl /usr/local/bin/
# sudo chmod +x /usr/local/bin/calicoctl
# deprecated: calicoctl pool add 192.168.0.0/16
# calicoctl node run --node-image=calico/node:v3.8.1 --config=calico.cfg -e ETCD_ENDPOINTS=http://127.0.0.1:2379,http://127.0.0.2:2379
# calicoctl apply -f ./calico-ippool.yaml

# docker network create --driver calico --subnet=192.168.0.0/16 --ipam-driver calico-ipam hadoop-net
# docker run -d --net hadoop-net --name master --hostname master cloudsuite/data-analytics master

# general idea: create calico network for CIDR 192.168.0.0/16 and then containers simply find each other via their hostnames
# https://docs.projectcalico.org/v3.8/reference/resources/ippool
# https://docs.projectcalico.org/v3.8/reference/resources/networkpolicy
# calicoctl apply...

# Ok, whatever - try instead with taints/tolerations and run in the same K8s cluser, see - https://kubernetes.io/docs/concepts/configuration/taint-and-toleration/
