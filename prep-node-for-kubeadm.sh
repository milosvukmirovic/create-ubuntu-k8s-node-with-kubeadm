#!/bin/bash
#
#
#*#*#*#*#*#*#*#*##*#*#*#*#*#*##*#*#*#*#*#*#*#*#*#*#*#*#*#*#
#Script to:
#create k8s and containerd .conf files
#install via apt kube{adm,let,ctl}, containerd, and docker

#*#*#*#*#*#*#*#*#*#*#*#*#*#*#*#*#*#*#*#*#*#*#*#*#*#*#*#*#*#

Check if user is root or has sudo powers:

if [[ $(whoami) != 'root' ]] && [[ ! $(groups | grep -o -e sudo) ]]
then
    sudo -v
    [[ $? = '0' ]] && echo "You have sudo privileges" || exit
else
    [[ $(whoami) = 'root' ]] && echo "You are root user" || echo "You have sudo privileges"
fi

####Disable swap
sudo sed -i '/swap/d' /etc/fstab
sudo swapoff -a

#We need br_netfilter module loaded. This is to ensure it:
sudo modprobe br_netfilter

#We need our node's iptables to correctly see bridged traffic:

cat <<EOF | sudo tee /etc/modules-load.d/k8s.conf
br_netfilter
EOF

cat <<EOF | sudo tee /etc/sysctl.d/k8s.conf
net.bridge.bridge-nf-call-ip6tables = 1
net.bridge.bridge-nf-call-iptables = 1
EOF

sudo sysctl --system

#####Docker, Containerd, and their configurations:

cat <<EOF | sudo tee /etc/modules-load.d/containerd.conf
overlay
br_netfilter
EOF

sudo modprobe overlay

cat <<EOF | sudo tee /etc/sysctl.d/99-kubernetes-cri.conf
net.bridge.bridge-nf-call-iptables  = 1
net.ipv4.ip_forward                 = 1
net.bridge.bridge-nf-call-ip6tables = 1
EOF

#Prereqs for apt installations:

#Necessary prerequisite packages:
sudo apt-get update && apt-get install apt-transport-https ca-certificates curl gnupg lsb_release -y
#Adding necessary keys, including for Kubernetes source as well:
sudo curl -fsSLo /usr/share/keyrings/kubernetes-archive-keyring.gpg https://packages.cloud.google.com/apt/doc/apt-key.gpg
sudo curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --dearmor -o /usr/share/keyrings/docker-archive-keyring.gpg

#Including Kubernetes source here as well to group it with docker:
echo "deb [signed-by=/usr/share/keyrings/kubernetes-archive-keyring.gpg] https://apt.kubernetes.io/ kubernetes-xenial main" | sudo tee /etc/apt/sources.list.d/kubernetes.list
echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/docker-archive-keyring.gpg] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable" | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null

#Installing and verifying docker and containerd
sudo apt-get update
sudo apt-get install docker-ce docker-ce-cli containerd.io -y
sudo docker run hello-world
sudo mkdir -p /etc/containerd
sudo containerd config default | sudo tee /etc/containerd/config.toml
sudo systemctl restart containerd

#Use Systemd cgroup driver:
sed -i 's/SystemdCgroup = false/SystemdCgroup = true/g' /etc/containerd/config.toml
#This seems to be a hit or miss, to be revised:
sed -i '/\[plugins\.\"io\.containerd\.grpc\.v1\.cri\"\.containerd\.runtimes\.runc\.options\]/ a \ \ \ \ \ \ \ \ \ \ \ \ SystemdCgroup = true' /etc/containerd/config.toml
#This seems reliable:
echo '{"exec-opts": ["native.cgroupdriver=systemd"]}' >> /etc/docker/daemon.json
sudo systemctl restart docker.service


#Install kubeadm, kubelet, kubectl:
sudo apt-get update
sudo apt-get install -y kube{let,adm,ctl}
sudo apt-mark hold kube{let,adm,ctl}

echo -e "Ready to initialize Cluster and create Master node with kubeadm init,\nOr:\nJoin node with kubeadm join followed by IP address and port of the Master and tokens."


