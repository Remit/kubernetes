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

# Creating the directory for the analysis
if [ ! -d analysis ]; then
  mkdir analysis
fi

echo "[$(date)] parsec benchmarking starts..."
# looping over available configurations...
for podconfig in *.yaml
do
  # If the file is not a directory...
    echo "[$(date)] benchmarking with ${podconfig}"
    # Making the directory to store the results for a particular test (if does not exist)
    resfname=results/${podconfig%.*}

    if [ ! -d ${resfname} ]; then
      mkdir ${resfname}
    fi

    # Conducting test nruns times and collecting the results whenever the processing is finished
    i=1
    while [ "$i" -le "$nruns" ]
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
      while ! ${benchdone}
      do
        sleep 1 ;

        status=$(sudo kubectl --kubeconfig /etc/kubernetes/admin.conf describe pod ${podname} | grep Status | sed -n '1 p' | cut -d":" -f 2 | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')

        if [ "$status" = "Succeeded" ]; then
          benchdone=true
        fi
      done

      # Redirecting the results to the log file
      sudo kubectl --kubeconfig /etc/kubernetes/admin.conf logs ${podname} | sudo tee ${testrunres} > /dev/null

      # Terminating the pod
      sudo kubectl --kubeconfig /etc/kubernetes/admin.conf delete pod ${podname} --force --grace-period=0

      echo "[$(date)] benchmarking with ${podconfig}: finishing run ${i} of pod ${podname}, the results are stored in file ${testrunres}"
      i=$(( i + 1 ))
    done
done

docker system prune -a -f
sudo Rscript ${kubernetescode}/scripts/ParsecLogsAnalysis.R --benchmarkpath=${kubernetescode}/benchmarks/parsec --analysispath=${kubernetescode}/benchmarks/parsec/analysis
echo "[$(date)] parsec benchmarking completed!"
