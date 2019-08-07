#!/bin/sh

sudo kubeadm reset
docker volume rm $(docker volume ls -qf dangling=true)
