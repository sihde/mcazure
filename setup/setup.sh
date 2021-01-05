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
systemctl enable minecraft@1.16.4.service
systemctl add-wants multi-user.target minecraft@1.16.4.service

apt-get update
apt-get -y upgrade --with-new-pkgs
apt-get -y install zulu8-jre-headless azure-cli
apt-get -y autoremove --purge

# Create user
adduser --disabled-login --quiet --home /srv/minecraft --no-create-home minecraft --gecos ""
mkdir -p /srv

# Add mount point for home directory
cat >> /etc/fstab <<EOF
UUID=e0698c68-30d0-482a-9615-a6278be757b4 /srv ext4 defaults 0 2
EOF

# Log in with user-assigned managed identity that has KeyVault access
az login --allow-no-subscriptions --identity \
  -u '/subscriptions/32c8a58f-efa7-4fee-8245-180c4c11257b/resourceGroups/mc-storage/providers/Microsoft.ManagedIdentity/userAssignedIdentities/hamachi-mc-id'

# download ssh host keys from KeyVault and configure ssh server to use them
az keyvault secret download --vault-name hamachi-mc-vault --name host-key-ed25519 \
  --file hamachi-mc_ed25519_key
chmod 0600 hamachi-mc_ed25519_key
mv hamachi-mc_ed25519_key /etc/ssh/
ssh-keygen -y -f /etc/ssh/hamachi-mc_ed25519_key > /etc/ssh/hamachi-mc_ed25519_key.pub
patch /etc/ssh/sshd_config sshd_config.diff 
dpkg-reconfigure -f noninteractive openssh-server
