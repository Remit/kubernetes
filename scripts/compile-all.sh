#!/bin/bash
# The script is executed to compile Kubernetes for the first time
# Arguments:
# 1 - path to kubernetes code

kubernetescode='.'

if [[ ! -z "$1" ]]
  then
    kubernetescode=$1
fi

cd $kubernetescode
pwd
git pull

# The command below makes a dockerized build and copies compiled binaries
# to _output/dockerized/bin/linux/amd64/ dir
sudo ./build/run.sh make

# Moving the compiled binaries to the bin folder for further execution
sudo mv _output/dockerized/bin/linux/amd64/* /usr/bin/

# Freeing the space
sudo rm -rf _output/
