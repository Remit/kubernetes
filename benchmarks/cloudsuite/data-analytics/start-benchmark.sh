# https://docs.projectcalico.org/v3.8/getting-started/bare-metal/installation/container
# Calico network for container? to connect to calico for pods?
# https://kubernetes.io/docs/concepts/services-networking/network-policies/
# https://docs.projectcalico.org/v3.8/security/calico-network-policy
# install calicoctl:
# curl -O -L  https://github.com/projectcalico/calicoctl/releases/download/v3.8.1/calicoctl
# sudo cp calicoctl /usr/local/bin/
#sudo chmod +x /usr/local/bin/calicoctl
# deprecated: calicoctl pool add 192.168.0.0/16
# calicoctl node run --node-image=calico/node:v3.8.1

# general idea: create calico network for CIDR 192.168.0.0/16 and then containers simply find each other via their hostnames
# https://docs.projectcalico.org/v3.8/reference/resources/ippool
# https://docs.projectcalico.org/v3.8/reference/resources/networkpolicy
# calicoctl apply... 
