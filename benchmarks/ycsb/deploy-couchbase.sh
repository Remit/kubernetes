#!/bin/sh
# Script to deploy the couchbase service exposed to communicate with the outside world (load-driving machine)

sudo kubectl --kubeconfig /etc/kubernetes/admin.conf apply -f benchmarks/ycsb/couchbase-test.yaml
# sudo kubectl --kubeconfig /etc/kubernetes/admin.conf expose deployment couchbase-deployment --type=NodePort --name=couchbase-service
sudo kubectl --kubeconfig /etc/kubernetes/admin.conf apply -f benchmarks/ycsb/couchbase-service.yaml
# To get port mappings
sudo kubectl --kubeconfig /etc/kubernetes/admin.conf describe service couchbase-service

# TODO: service with stable port mapping
# TODO: initialize all with curl to service https://docs.couchbase.com/server/current/install/init-setup.html#initialize-cluster-rest
