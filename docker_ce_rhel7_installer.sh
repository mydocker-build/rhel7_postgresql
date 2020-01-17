#!/bin/bash
echo "Uninstall old Docker........................................."
sudo yum -y remove \
    docker \
    docker-client \
    docker-client-latest \
    docker-common \
    docker-latest \
    docker-latest-logrotate \
    docker-logrotate \
    docker-engine
	
echo "Install required packages...................................."
sudo yum -y install \
    yum-utils \
    device-mapper-persistent-data \
    lvm2

echo "Setup Docker CE stable repository............................"
sudo yum-config-manager \
    --add-repo \
    https://download.docker.com/linux/centos/docker-ce.repo

echo "Install container-selinux as for requirement................."
yum -y install http://mirror.centos.org/centos/7/extras/x86_64/Packages/container-selinux-2.107-3.el7.noarch.rpm

echo "Install latest docker CE....................................."
sudo yum -y install \
    docker-ce \
    docker-ce-cli \
    containerd.io

echo "Configure direct-lvm mode...................................."
sudo pvcreate /dev/sdb /dev/sdc
sudo vgcreate docker /dev/sdb /dev/sdc
sudo lvcreate --wipesignatures y -n thinpool docker -l 95%VG
sudo lvcreate --wipesignatures y -n thinpoolmeta docker -l 1%VG
sudo lvconvert -y \
    --zero n \
    -c 512K \
    --thinpool docker/thinpool \
    --poolmetadata docker/thinpoolmeta
cat > /etc/lvm/profile/docker-thinpool.profile <<'EOF'
activation {
  thin_pool_autoextend_threshold=80
  thin_pool_autoextend_percent=20
}
EOF
sudo lvchange --metadataprofile docker-thinpool docker/thinpool
sudo lvs -o+seg_monitor
sudo lvchange --monitor y docker/thinpool
mkdir -p /etc/docker
cat > /etc/docker/daemon.json <<'EOF'
{
    "storage-driver": "devicemapper",
    "storage-opts": [
    "dm.thinpooldev=/dev/mapper/docker-thinpool",
    "dm.use_deferred_removal=true",
    "dm.use_deferred_deletion=true"
   ]
}
EOF

echo "Enable and start docker service..............................."
systemctl enable docker --now

echo "Install Docker Compose........................................"
sudo curl -L "https://github.com/docker/compose/releases/download/1.25.0/docker-compose-$(uname -s)-$(uname -m)" -o /usr/local/bin/docker-compose
sudo chmod +x /usr/local/bin/docker-compose

echo "You have been finished Docker CE and Docker Compose Installation!"
