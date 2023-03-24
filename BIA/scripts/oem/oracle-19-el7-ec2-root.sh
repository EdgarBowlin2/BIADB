#!/usr/bin/env bash

#  OPERATING SYSTEM CHANGES
#  packages
yum-config-manager --enable rhui-REGION-rhel-server-optional
yum install wget -y
rpm -Uvh https://dl.fedoraproject.org/pub/epel/epel-release-latest-7.noarch.rpm
yum-config-manager --enable epel
yum clean all
yum update -y

yum install dos2unix -y
yum install firewalld -y
yum install lsof -y
yum install jq -y
yum install mlocate -y
yum install nvme-cli -y
yum install psmisc -y
yum install sssd -y
yum install tmux -y
yum install unzip -y
yum install zip -y

yum install bc -y                         # 12 19
yum install binutils.x86_64 -y            # 11 12 19
yum install compat-libcap1.x86_64 -y      # 11 12 19
yum install compat-libstdc++-33.x86_64 -y # 11 12 19
yum install elfutils-libelf -y            # 19
yum install elfutils-libelf-devel -y      # 19
yum install fontconfig-devel -y           # 19
yum install gcc -y                        # 11
yum install gcc-c++ -y                    # 11
yum install glibc.x86_64 -y               # 11 12 19
yum install glibc-devel.x86_64 -y         # 11 12 19
yum install java-1.8.0 -y                 # osbws
yum install ksh -y                        # 11 12 19
yum install libaio.x86_64 -y              # 11 12 19
yum install libaio-devel.x86_64 -y        # 11 12 19
yum install libgcc.x86_64 -y              # 11 12 19
yum install libstdc++.x86_64 -y           # 11 12 19
yum install libstdc++-devel.x86_64 -y     # 11 12 19
yum install libxcb.x86_64 -y              # 12 19
yum install libX11.x86_64 -y              # 12 19
yum install libXau.x86_64 -y              # 12 19
yum install libXi.x86_64 -y               # 12 19
yum install libXtst.x86_64 -y             # 12 19
yum install libXrender.x86_64 -y          # 12 19
yum install libXrender-devel.x86_64 -y    # 12 19
yum install make.x86_64 -y                # 11 12 19
yum install net-tools.x86_64 -y           # 12
yum install nfs-utils.x86_64 -y           # 12
yum install smartmontools.x86_64 -y       # 12 19
yum install sysstat.x86_64 -y             # 11 12 19

#  hostname
IP_ADDRESS=$(curl -s "http://169.254.169.254/latest/meta-data/local-ipv4")

read -p "HOSTNAME: " DNSNAME
SHORTNAME=$(echo $DNSNAME | cut -d. -f1)
hostnamectl set-hostname $DNSNAME
echo "$IP_ADDRESS   $DNSNAME $SHORTNAME" >>/etc/hosts
echo "HOSTNAME=$DNSNAME" >>/etc/sysconfig/network

#  firewalld
systemctl mask iptables
systemctl enable firewalld
service firewalld start

setenforce 0
firewall-cmd --add-port=1521/tcp --set-short="Ingress Rule for Database" --permanent
firewall-cmd --add-port=3872/tcp --set-short="Ingress Rule for OEM Agent" --permanent
firewall-cmd --reload
setenforce 1

#  disable transparent hugepages
sed -i '/GRUB_CMDLINE_LINUX/ s/\"$/ transparent_hugepage=never\"/g' /etc/default/grub
grub2-mkconfig -o /boot/grub2/grub.cfg

#  set hugepages
cat <<EOT >/etc/sysctl.d/96-hugepages-sysctl.conf
vm.nr_hugepages = 3076
EOT

sysctl --system

#  users
groupadd -g 5001 oinstall
groupadd -g 5002 dba
useradd -u 5000 -g oinstall -G dba oracle

echo "umask 022" >>/home/oracle/.bash_profile
echo "export ORACLE_BASE=/u01/app/oracle" >>/home/oracle/.bash_profile
echo "export PS1='[\u@\h (\$ORACLE_SID) \W]$ '" >>/home/oracle/.bash_profile

#  ORACLE CHANGES
#  sysctl
SHMALL=$(expr $(grep MemTotal /proc/meminfo | awk '{ print $2 }') \* 1024 / 4096 \* 4 / 10)
SHMMAX=$(expr $(grep MemTotal /proc/meminfo | awk '{ print $2 }') \* 1024 \* 5 / 10)
MEMLOCK=$(expr $(grep MemTotal /proc/meminfo | awk '{ print $2 }') \/ 100 \* 90)

cat <<EOT >/etc/sysctl.d/97-oracledatabase-sysctl.conf
fs.aio-max-nr = 1048576
fs.file-max = 6815744
kernel.shmall = $SHMALL
kernel.shmmax = $SHMMAX
kernel.shmmni = 4096
kernel.sem = 250 32000 100 128
net.ipv4.ip_local_port_range = 9000 65500
net.core.rmem_default = 262144
net.core.rmem_max = 4194304
net.core.wmem_default = 262144
net.core.wmem_max = 1048576
EOT

sysctl --system

#  limits
cat <<EOT >/etc/security/limits.d/97-oracledatabase-limits.conf
oracle           soft    nofile          1024
oracle           hard    nofile          65536
oracle           soft    nproc           2047
oracle           hard    nproc           16384
oracle           soft    stack           10240
oracle           hard    stack           32768
oracle           soft    memlock         $MEMLOCK
oracle           hard    memlock         $MEMLOCK
EOT

#  oraInst
cat <<EOT >/etc/oraInst.loc
inventory_loc=/u01/app/oraInventory
inst_group=oinstall
EOT

#  oracle directory structure
mkdir -p /u01/app/oraInventory
mkdir -p /u01/app/oracle
chown -R oracle:oinstall /u01/app/oraInventory
chown -R oracle:oinstall /u01/app/oracle
chmod -R 775 /u01
chown oracle:oinstall /backup
chmod 775 /backup
