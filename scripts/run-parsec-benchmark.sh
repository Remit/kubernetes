#!/bin/sh

# Script that runs parsec benchmark on the deployed Kubernetes cluster.
# Yaml files for deploying benchmark pods are stored in <kubernetescode>/benchmarks/parsec/
# Each test runs N times (10 - by default)

# Arguments:
# 1 - path to kubernetes code
# 2 - number of test runs

kubernetescode='.'
nruns=10

if [ ! -z "$1" ]
  then
    kubernetescode=$1
fi

if [ ! -z "$2" ]
  then
    nruns=$2
fi

cd ${kubernetescode}/benchmarks/parsec

# Creating the directory for the results
if [ ! -d results ]; then
  mkdir results
fi

echo "[$(date)] parsec benchmarking starts..."
# looping over available configurations...
for podconfig in $(dir)
do
  # If the file is not a directory...
  if [ ! -d $podfonfig ]; then
    echo "[$(date)] benchmarking with ${podconfig}"
    # Making the directory to store the results for a particular test (if does not exist)
    resfname=results/${podconfig%.*}

    if [ ! -d ${resfname} ]; then
      mkdir ${resfname}
    fi

    # Conducting test nruns times and collecting the results whenever the processing is finished
    for i in {1..${nruns}}
    do
      # Preparing for the run
      echo "[$(date)] benchmarking with ${podconfig}: starting run ${i}"
      testrunres=${resfname}/${i}.log
      # Taking first line found by 'name', cutting it by ":" and taking second part thereof (value) + removing whitespaces
      podname=$(cat ${podconfig} | grep name | sed -n '1 p' | cut -d":" -f 2 | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')

      # Starting the benchmark
      sudo kubectl --kubeconfig /etc/kubernetes/admin.conf apply -f ${podconfig}

      # Waiting till the benchmark is done
      benchdone=false
      while [ ! $benchdone ]; do
        sleep 60 ;

        status=$(sudo kubectl --kubeconfig /etc/kubernetes/admin.conf describe pod ${podname} | grep Status | sed -n '1 p' | cut -d":" -f 2 | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')

        if [ status == "Succeeded" ]; then
          benchdone=true
        else
          benchdone=false
        fi
      done

      # Redirecting the results to the log file
      sudo kubectl --kubeconfig /etc/kubernetes/admin.conf logs ${podname} > ${testrunres}

      # Terminating the pod
      sudo kubectl --kubeconfig /etc/kubernetes/admin.conf delete pod ${podname} --force --grace-period=0

      echo "[$(date)] benchmarking with ${podconfig}: finishing run ${i}, the results are stored in file ${testrunres}"
    done
  fi
done

docker system prune -a -f
echo "[$(date)] parsec benchmarking completed!"
