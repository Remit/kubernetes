#!/bin/bash
# The script:
# - installs tools necessary for development in Kubernetes
# - sets up settings for Kubernetes to run
# - clones the github repo
# Arguments:
# 1 - path to kubernetes code

kubernetescode='.'

if [ ! -z "$1" ]
  then
    kubernetescode=$1
  else
    echo "You did not specify the path to the Kubernetes code. Exiting..."
    exit 1
fi

cd $(kubernetescode)

# Installing golang
echo "[$(date)] Installing golang..."
wget https://dl.google.com/go/go1.12.6.linux-amd64.tar.gz
sudo tar -C /usr/local -xzf go1.12.6.linux-amd64.tar.gz
rm -f go1.12.6.linux-amd64.tar.gz
echo "[$(date)] golang installed"

# Installing make
echo "[$(date)] Installing make..."
sudo apt -y install make
echo "[$(date)] make installed"

# Installing gcc
echo "[$(date)] Installing gcc..."
sudo apt -y install gcc
echo "[$(date)] gcc installed"

# Installing Docker CE
echo "[$(date)] Installing Docker CE..."
sudo apt-get update
sudo apt-get -y install apt-transport-https ca-certificates curl gnupg-agent software-properties-common
curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo apt-key add -
sudo add-apt-repository "deb [arch=amd64] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable"
sudo apt-get update
sudo apt-get -y install docker-ce docker-ce-cli containerd.io
echo "[$(date)] Docker CE installed"

# Installing etcd
echo "[$(date)] Installing etcd with Kubernetes script..."
hack/install-etcd.sh
echo "[$(date)] etcd installed"

# Setting up paths for seamless compilation and execution of Kubernetes
echo "[$(date)] Setting paths..."
export PATH=$PATH:/usr/local/go/bin:$(pwd)/third_party/etcd/:$(pwd)/_output/bin/
echo "export PATH=$PATH:/usr/local/go/bin:$(pwd)/third_party/etcd/:$(pwd)/_output/bin/" >> ~/.bashrc
echo "Defaults secure_path=\"$(sudo cat /etc/sudoers | grep "secure_path" | cut -d'"' -f 2):usr/local/go/bin:$(pwd)/third_party/etcd/:$(pwd)/_output/bin/\"" | sudo tee /etc/sudoers.d/10-visudo-settings
echo "[$(date)] paths set"

# Setting up Docker CE
echo "[$(date)] Setting Docker CE..."
sudo usermod -a -G docker ubuntu
sudo systemctl start docker
echo "[$(date)] Docker CE set"

# Preparing CNI (reference - https://github.com/Remit/kubernetes/blob/feature-cpupinning-augmented/build/rpms/kubernetes-cni.spec)
echo "[$(date)] Preparing common CNI files..."
sudo mkdir -p /etc/cni/net.d
sudo mkdir -p /opt/cni/bin
wget https://storage.googleapis.com/kubernetes-release/network-plugins/cni-plugins-amd64-v0.7.5.tgz
sudo tar -C /opt/cni/bin -xzf cni-plugins-amd64-v0.7.5.tgz
rm -f cni-plugins-amd64-v0.7.5.tgz
echo "[$(date)] Common CNI files are prepared"

# Preparing custom kubelet service that will point at the binaries that we will compile later
echo "[$(date)] Preparing custom kubelet service..."
sudo cp build/rpms/kubelet.service /etc/systemd/system/
sudo mkdir -p /etc/systemd/system/kubelet.service.d/
sudo cp build/rpms/10-kubeadm.conf /etc/systemd/system/kubelet.service.d/
echo "[$(date)] Custom kubelet service is prepared"

# Installing R for analysis and benchmark generation scripts
echo "[$(date)] Installing R for benchmark configs generation and results analysis..."
sudo apt-get -y install r-base
sudo chmod o+w /usr/local/lib/R/site-library/
echo "install.packages(\"readr\", repos=\"https://cran.rstudio.com\")" | R --no-save
echo "install.packages(\"data.table\", repos=\"https://cran.rstudio.com\")" | R --no-save
echo "install.packages(\"magrittr\", repos=\"https://cran.rstudio.com\")" | R --no-save
echo "install.packages(\"dplyr\", repos=\"https://cran.rstudio.com\")" | R --no-save
echo "install.packages(\"ggplot2\", repos=\"https://cran.rstudio.com\")" | R --no-save
echo "install.packages(\"gtools\", repos=\"https://cran.rstudio.com\")" | R --no-save
echo "[$(date)] R installed"

# Done
echo "[$(date)] Environment prepared"
echo "INFO: Remember to check whether the correct host is used in /etc/hostname and /etc/hosts !"
