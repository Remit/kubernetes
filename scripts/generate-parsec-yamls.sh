#!/bin/bash

# Script that generates yaml pods specifications for parsec benchmark

# Arguments:
# 1 - path to kubernetes code

# Comments:
# - for guaranteed (gu) QoS class gu.requests and gu.limits should be same
# - for guaranteed (bu) QoS class bu.limits should be higher than bu.requests
# The generation settings should be set below in call to Rscript

kubernetescode='.'

if [ ! -z "$1" ]
  then
    kubernetescode=$1
fi

if [ ! -d $kubernetescode/benchmarks/parsec ]; then
  sudo mkdir /benchmarks/parsec
fi

if [ $(ls /usr/bin/ | grep Rscript) = "Rscript" ]; then
  sudo Rscript ParsecYamlGeneration.R \
  --templatefile=${kubernetescode}/scripts/template.yaml \
  --yamldir=${kubernetescode}/benchmarks/parsec \
  --programs=blackscholes,bodytrack,canneal,dedup,facesim,ferret,fluidanimate,freqmine,raytrace,streamcluster,swaptions,vips,x264 \
  --sizes=simmedium \
  --qos=besteffort,burstable,guaranteed \
  --labels=separate,numaaware,stackposaware \
  --gu.requests=0.5,4Gi \
  --gu.limits=0.5,4Gi \
  --bu.requests=0.5,4Gi \
  --bu.limits=1,8Gi
else
  echo "R is not installed. Rscript should be in /usr/bin."
fi
