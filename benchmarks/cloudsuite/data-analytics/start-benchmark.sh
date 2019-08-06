# https://docs.projectcalico.org/v3.8/getting-started/bare-metal/installation/container
# Calico network for container? to connect to calico for pods?
# https://kubernetes.io/docs/concepts/services-networking/network-policies/
# https://docs.projectcalico.org/v3.8/security/calico-network-policy

# install etcd:
# For reference https://computingforgeeks.com/how-to-install-etcd-on-ubuntu-18-04-ubuntu-16-04/

# install calicoctl:
# curl -O -L  https://github.com/projectcalico/calicoctl/releases/download/v3.8.1/calicoctl
# sudo cp calicoctl /usr/local/bin/
# sudo chmod +x /usr/local/bin/calicoctl
# deprecated: calicoctl pool add 192.168.0.0/16
# calicoctl node run --node-image=calico/node:v3.8.1 --config=calico.cfg -e ETCD_ENDPOINTS=http://127.0.0.1:2379,http://127.0.0.2:2379
# calicoctl apply -f ./calico-ippool.yaml

# docker network create --driver calico --subnet=192.168.0.0/16 --ipam-driver calico-ipam hadoop-net
# docker run -d --net hadoop-net --name master --hostname master cloudsuite/data-analytics master

# general idea: create calico network for CIDR 192.168.0.0/16 and then containers simply find each other via their hostnames
# https://docs.projectcalico.org/v3.8/reference/resources/ippool
# https://docs.projectcalico.org/v3.8/reference/resources/networkpolicy
# calicoctl apply...

# Ok, whatever - try instead with taints/tolerations and run in the same K8s cluser, see - https://kubernetes.io/docs/concepts/configuration/taint-and-toleration/
