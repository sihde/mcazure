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

# Minecraft systemd configuration
cp minecraft@.service /etc/systemd/system/
systemctl enable minecraft@1.16.4.service
systemctl add-wants multi-user.target minecraft@1.16.4.service

apt-get update
apt-get -y upgrade --with-new-pkgs
apt-get -y install zulu8-jre-headless
apt-get -y autoremove --purge

# Create user
adduser --disabled-login --quiet --home /srv/minecraft --no-create-home minecraft --gecos ""
mkdir -p /srv

# Add mount point for home directory
cat >> /etc/fstab <<EOF
UUID=e0698c68-30d0-482a-9615-a6278be757b4 /srv ext4 defaults 0 2
EOF
