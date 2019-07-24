#!/bin/sh

# Test run of a benchmark
# Arguments:
# 1 - path to kubernetes code

kubernetescode='.'

if [ ! -z "$1" ]
  then
    kubernetescode=$1
fi

cd $(kubernetescode)

sudo kubectl --kubeconfig /etc/kubernetes/admin.conf apply -f $(kubernetescode)/benchmarks/parsec/cpuman-perf-test-parsec-pod.yaml
