#!/bin/sh
# Script to deploy the couchbase service exposed to communicate with the outside world (load-driving machine)

sudo kubectl --kubeconfig /etc/kubernetes/admin.conf apply -f benchmarks/ycsb/couchbase-simplest.yaml
# sudo kubectl --kubeconfig /etc/kubernetes/admin.conf expose deployment couchbase-deployment --type=NodePort --name=couchbase-service
sudo kubectl --kubeconfig /etc/kubernetes/admin.conf apply -f benchmarks/ycsb/couchbase-service.yaml
# To get port mappings
sudo kubectl --kubeconfig /etc/kubernetes/admin.conf describe service couchbase-service

echo "Waiting 1.5 minutes for Couchbase to become up before proceeding to user creations..."
sleep 90

# Couchbase Starting
# Reference: https://docs.couchbase.com/server/current/install/init-setup.html#initialize-cluster-rest

# Creating admin user
curl -v -X POST http://127.0.0.1:8091/settings/web -d password=mowgli19 -d username=carlos -d port=SAME
# Settings for Couchbase
curl -u carlos:mowgli19 -X POST http://127.0.0.1:8091/pools/default -d memoryQuota=1024 -d indexMemoryQuota=256

# Creating a bucket
# Reference: https://docs.couchbase.com/server/6.0/rest-api/rest-bucket-create.html
# Reference: https://docs.couchbase.com/operator/1.2/couchbase-cluster-config.html#iopriority (ioPriority is somehow not present in the documentation on REST API)
curl -u carlos:mowgli19 -X POST http://127.0.0.1:8091/pools/default/buckets -d name=ycsb -d ramQuotaMB=512 -d bucketType=couchbase -d flushEnabled=1 -d ioPriority=high

# Setting up RBAC for Couchbase
curl -X PUT --data "name=ycsb&roles=bucket_full_access[ycsb]&password=mowgli19" -H "Content-Type: application/x-www-form-urlencoded" http://carlos:mowgli19@127.0.0.1:8091/settings/rbac/users/local/ycsb

# Setting autofailover
curl -u carlos:mowgli19 -i -X POST http://127.0.0.1:8091/settings/autoFailover -d 'enabled=true&timeout=30'
