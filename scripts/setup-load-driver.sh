#!/bin/bash
# This script is provided to setup the load driving machine running Ubuntu Linux.
# The script starts Workload-API in Docker container.
# More information: https://omi-gitlab.e-technik.uni-ulm.de/mowgli/workload-API

IP='localhost'

if [ ! -z "$1" ]
  then
    IP=$1
fi

# Installing Docker CE
echo "[$(date)] Installing Docker CE..."
sudo apt-get update
sudo apt-get install apt-transport-https ca-certificates curl gnupg-agent software-properties-common
curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo apt-key add -
sudo add-apt-repository "deb [arch=amd64] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable"
sudo apt-get update
sudo apt-get install docker-ce docker-ce-cli containerd.io
echo "[$(date)] Docker CE installed"

# Starting Workload-API server
echo "[$(date)] Downloading Docker images and starting Workload-API server..."
docker run -d -p 8181:8181 -e PUBLIC_IP=${IP} -e INFLUXDB_URL=1.2.3.4:5555 -v /tmp:/opt/results -v /tmp:/var/log omi-registry.e-technik.uni-ulm.de/mowgli/workload-api:latest
echo "[$(date)] Workload-API server started in Docker container. Test it by opening http://<<PUBLIC_IP>>:8181/v1/swagger.json in the browser or by sending a GET request."
