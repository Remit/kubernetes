#!/bin/sh
# Script to undeploy couchbase to avoid problems with data overwrite in the database (might end up in error!)
sudo kubectl --kubeconfig /etc/kubernetes/admin.conf delete service couchbase-service
sudo kubectl --kubeconfig /etc/kubernetes/admin.conf delete deployment couchbase-deployment
