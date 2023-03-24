#!/usr/bin/env bash

#  VARIABLES
GRID_HOME=/u01/app/oracle/product/19.0.0/grid
ORACLE_HOME=/u01/app/oracle/product/19.0.0/db

#  remove password expiration from ec2-user
chage -M -1 -E -1 ec2-user

#  va certificate
dnf install wget -y

wget -P /etc/pki/ca-trust/source/anchors/ \
    http://crl.pki.va.gov/PKI/AIA/VA/VA-Internal-S2-RCA1-v1.cer \
    http://crl.pki.va.gov/PKI/AIA/VA/VA-Internal-S2-ICA1-v1.cer \
    http://aia.pki.va.gov/PKI/AIA/VA/VA-Internal-S2-ICA4.cer \
    http://aia.pki.va.gov/PKI/AIA/VA/VA-Internal-S2-ICA5.cer \
    http://aia.pki.va.gov/PKI/AIA/VA/VA-Internal-S2-ICA6.cer \
    http://aia.pki.va.gov/PKI/AIA/VA/VA-Internal-S2-ICA7.cer \
    http://aia.pki.va.gov/PKI/AIA/VA/VA-Internal-S2-ICA8.cer \
    http://aia.pki.va.gov/PKI/AIA/VA/VA-Internal-S2-ICA9.cer \
    http://aia.pki.va.gov/PKI/AIA/FederalPKI/FedCPG2SHA384.crt \
    http://aia.pki.va.gov/PKI/AIA/SSP/VerizonA2SHA384.cer \
    http://aia.pki.va.gov/PKI/AIA/SSP/TreasuryCASHA384.cer \
    http://aia.pki.va.gov/PKI/AIA/SSP/EntrustCASHA384.cer \
    http://aia.pki.va.gov/PKI/AIA/3party/DigiCertSHA384.cer
update-ca-trust enable
update-ca-trust extract

#  packages
dnf install https://dl.fedoraproject.org/pub/epel/epel-release-latest-8.noarch.rpm -y
dnf clean all
dnf update -y

#  utility packages
dnf install cloud-utils-growpart -y
dnf install dos2unix -y
dnf install firewalld -y
dnf install java-1.8.0 -y
dnf install lsof -y
dnf install jq -y
dnf install mlocate -y
dnf install nfs-utils -y
dnf install nvme-cli -y
dnf install postfix -y
dnf install psmisc -y
dnf install sendmail -y
dnf install sssd -y
dnf install tmux -y
dnf install unzip -y
dnf install zip -y
dnf install zstd -y

#  oracle packages
dnf install bc -y
dnf install binutils -y
dnf install elfutils-libelf -y
dnf install elfutils-libelf-devel -y
dnf install fontconfig-devel -y
dnf install glibc -y
dnf install glibc-devel -y
dnf install ksh -y
dnf install libaio -y
dnf install libaio-devel -y
dnf install libgcc -y
dnf install libibverbs -y
dnf install libnsl -y
dnf install librdmacm -y
dnf install libstdc++ -y
dnf install libstdc++-devel -y
dnf install libxcb -y
dnf install libX11 -y
dnf install libXau -y
dnf install libXi -y
dnf install libXtst -y
dnf install libXrender -y
dnf install make -y
dnf install net-tools -y
dnf install perl -y
dnf install policycoreutils -y
dnf install policycoreutils-python-utils -y
dnf install smartmontools -y
dnf install sysstat -y

#  oracle asm packages
dnf install https://download.oracle.com/otn_software/asmlib/oracleasmlib-2.0.17-1.el8.x86_64.rpm -y
dnf install https://yum.oracle.com/repo/OracleLinux/OL8/addons/x86_64/getPackage/oracleasm-support-2.1.12-1.el8.x86_64.rpm -y
dnf install kmod-oracleasm -y

#  hostname
IP_ADDRESS=$(curl -s "http://169.254.169.254/latest/meta-data/local-ipv4")

read -p "HOSTNAME: " DNSNAME
SHORTNAME=$(echo $DNSNAME | cut -d. -f1)
hostnamectl set-hostname $DNSNAME
echo "$IP_ADDRESS   $DNSNAME $SHORTNAME" >>/etc/hosts
echo "HOSTNAME=$DNSNAME" >>/etc/sysconfig/network

#  firewalld
systemctl enable firewalld
service firewalld start

setenforce 0
firewall-cmd --add-port=1521/tcp --set-short="Ingress Rule for Database" --permanent
firewall-cmd --add-port=3872/tcp --set-short="Ingress Rule for OEM Agent" --permanent
firewall-cmd --add-service=https --permanent
firewall-cmd --add-masquerade --permanent
firewall-cmd --add-forward-port=port=443:proto=tcp:toport=1521 --permanent
firewall-cmd --reload
setenforce 1

#  users
groupadd -g 5001 oinstall
groupadd -g 5002 dba
useradd -u 5000 -g oinstall -G dba oracle
chage -M -1 -E -1 oracle

echo "umask 022" >>/home/oracle/.bash_profile
echo "export ORACLE_BASE=/u01/app/oracle" >>/home/oracle/.bash_profile
echo "export PS1='[\u@\h (\$ORACLE_SID) \W]$ '" >>/home/oracle/.bash_profile

#  disable transparent hugepages
sed -i '/GRUB_CMDLINE_LINUX/ s/\"$/ transparent_hugepage=never\"/g' /etc/default/grub
grub2-mkconfig -o /boot/grub2/grub.cfg

#  hugepages
cat <<EOT >/etc/sysctl.d/96-hugepages-sysctl.conf
vm.nr_hugepages = 3076
EOT

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

sysctl --system

#  oraInst
cat <<EOT >/etc/oraInst.loc
inventory_loc=/u01/app/oraInventory
inst_group=oinstall
EOT

#  oracle directory structure
mkdir -p /u01/app/oraInventory
mkdir -p $GRID_HOME
mkdir -p /u01/app/oracle
chown -R oracle:oinstall /u01/app/oraInventory
chown -R oracle:oinstall $GRID_HOME
chown -R oracle:oinstall /u01/app/oracle
chmod -R 775 /u01
