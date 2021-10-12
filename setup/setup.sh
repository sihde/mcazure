#!/bin/bash

set -e

# Timezone
ln -sf /usr/share/zoneinfo/America/Los_Angeles /etc/localtime
dpkg-reconfigure -f noninteractive tzdata

# Zulu JRE repository
cp zulu.list /etc/apt/sources.list.d/
cp zulu /etc/apt/preferences.d/
mkdir -p /usr/local/share/keyrings
cp RPM-GPG-KEY-azulsystems /usr/local/share/keyrings/

# Azure CLI repo
cp azure-cli.list /etc/apt/sources.list.d/
cp azure-cli /etc/apt/preferences.d/
cp microsoft.gpg /usr/local/share/keyrings/

# Minecraft systemd configuration
cp minecraft@.service /etc/systemd/system/
# Don't enable by default, since multiple hosts in the scale set
# would fight over the same instance
#systemctl enable minecraft@1.16.4.service
#systemctl add-wants multi-user.target minecraft@1.16.4.service

# Preseed debconf
echo sysstat sysstat/enable boolean true | debconf-set-selections

# Install and upgrade packages
apt-get update
apt-get -y upgrade --with-new-pkgs
apt-get -y install zulu8-jre-headless zulu17-jre-headless azure-cli sysstat cifs-utils
apt-get -y autoremove --purge

# Create user
adduser --disabled-login --quiet --home /srv/minecraft --no-create-home minecraft --gecos ""
mkdir -p /srv/srv-old

# Add mount point for home directory
# Comment out while switching to scale sets
#cat >> /etc/fstab <<EOF
#UUID=e0698c68-30d0-482a-9615-a6278be757b4 /srv/srv-old ext4 defaults 0 2
#EOF


# Log in with user-assigned managed identity that has KeyVault access
az login --identity \
  -u '/subscriptions/32c8a58f-efa7-4fee-8245-180c4c11257b/resourceGroups/mc-storage2/providers/Microsoft.ManagedIdentity/userAssignedIdentities/hamachi-mc-id'

# download ssh host keys from KeyVault and configure ssh server to use them
restore_umask=$(umask -p)
umask 0077
az keyvault secret download --vault-name hamachi-mc-vault --name host-key-ed25519 \
  --file hamachi-mc_ed25519_key
mv hamachi-mc_ed25519_key /etc/ssh/
# Get storage account key
az storage account keys list -g mc-storage2 -n hamachifiles --query "[0].value"|perl -pe 's#"([a-zA-Z0-9/+=]+)"#password=$1#' > /etc/smbcred.txt
$restore_umask
ssh-keygen -y -f /etc/ssh/hamachi-mc_ed25519_key > /etc/ssh/hamachi-mc_ed25519_key.pub

# Mount SMB share in fstab
mkdir -p /srv/minecraft
cat >> /etc/fstab <<EOF
//hamachifiles.file.core.windows.net/hamachi-mc-share /srv/minecraft cifs vers=3.0,seal,username=hamachifiles,cred=/etc/smbcred.txt,mfsymlinks,dir_mode=0777,file_mode=0777,noperm,uid=minecraft,gid=minecraft 0 2
EOF

# Patch adds HostKey directive for the new key
patch /etc/ssh/sshd_config sshd_config.diff 
dpkg-reconfigure -f noninteractive openssh-server

cat >> /home/sihde/.ssh/authorized_keys <<EOF
ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIL6bvTJwY3DJT1c2ukmUJMJaLvCQUHpall3zQRjOb/2M sihde@sihde-mn3.linkedin.biz
ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIKutxzLvxoo8rrwBgw/JWkPLewTpEGZDNqpPif7EpGit sihde@toocoo
ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIKqPM2vgeGCz30yywQpUKLBd2PW49v4gsZWdP8WdSEKE sihde@sihde-ld1.linkedin.biz
ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIHkUe9+nsoJNMhPWNXX8qzL9dq6NvcNuK8PvT19rvFrW sihde@DESKTOP-PPRJK48
ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAICLDrdUadTMo+pD0IgDOfDnkWMyamfbRkGcsXqsififK sihde@DESKTOP-IART6IV
ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAICI8eR8jWqi/fCbiXEWijGYbixK0ZdDMuEsBDUR9PgFT sihde@pixel5
EOF
