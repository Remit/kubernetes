#!/bin/sh
# Script to deploy the couchbase service exposed to communicate with the outside world (load-driving machine)

sudo kubectl --kubeconfig /etc/kubernetes/admin.conf apply -f benchmarks/ycsb/couchbase.yaml
sudo kubectl --kubeconfig /etc/kubernetes/admin.conf expose deployment couchbase-deployment --type=NodePort --name=couchbase-service
# To get port mappings
sudo kubectl --kubeconfig /etc/kubernetes/admin.conf describe service couchbase-service
