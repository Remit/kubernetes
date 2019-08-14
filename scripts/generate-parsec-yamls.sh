#!/bin/bash

# Script that generates yaml pods specifications for parsec benchmark

# Arguments:
# 1 - path to kubernetes code

# Comments:
# - for guaranteed (gu) QoS class gu.requests and gu.limits should be same
# - for guaranteed (bu) QoS class bu.limits should be higher than bu.requests
# The generation settings should be set below in call to Rscript

kubernetescode='.'
qosclasses=besteffort,burstable,guaranteed
sizes=simsmall,simmedium,simlarge
# also should use native but with smaller number of runs as each test can be (10-30 mins)

if [ ! -z "$1" ]
  then
    kubernetescode=$1
fi

if [ ! -z "$2" ]
  then
    qosclasses=$2
fi

if [ ! -z "$3" ]
  then
    sizes=$3
fi

if [ ! -d $kubernetescode/benchmarks/parsec ]; then
  sudo mkdir -p $kubernetescode/benchmarks/parsec
fi

if [ $(ls /usr/bin/ | grep Rscript) = "Rscript" ]; then
  sudo Rscript ParsecYamlGeneration.R \
  --templatefile=${kubernetescode}/scripts/template.yaml \
  --yamldir=${kubernetescode}/benchmarks/parsec \
  --programs=blackscholes,bodytrack,canneal,dedup,facesim,ferret,fluidanimate,freqmine,raytrace,streamcluster,swaptions,vips,x264 \
  --sizes=$sizes \
  --qos=$qosclasses \
  --labels=separate,numaaware,stackposaware \
  --gu.requests=4,16Gi \
  --gu.limits=4,16Gi \
  --bu.requests=4,16Gi \
  --bu.limits=8,32Gi
else
  echo "R is not installed. Rscript should be in /usr/bin."
fi
