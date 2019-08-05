#!/bin/sh
# The script is executed whenever the updates to kubelet code are introduced
# Arguments:
# 1 - path to kubernetes code

kubernetescode='.'

if [ ! -z "$1" ]
  then
    kubernetescode=$1
fi

cd $kubernetescode
git pull

# The command below makes a dockerized build and copies compiled binaries
# to _output/dockerized/bin/linux/amd64/ dir
sudo build/run.sh make kubelet KUBE_BUILD_PLATFORMS=linux/amd64

# Moving the compiled binaries to the bin folder for further execution
sudo mv _output/dockerized/bin/linux/amd64/* /usr/bin/

# Freeing the space
sudo rm -rf _output/
