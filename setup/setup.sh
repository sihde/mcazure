#!/bin/bash

set -e

cp zulu.list /etc/apt/sources.list.d/zulu.list
cp zulu /etc/apt/preferences.d/zulu
mkdir -p /usr/local/share/keyrings
cp RPM-GPG-KEY-azulsystems /usr/local/share/keyrings

apt-get update
apt-get -y upgrade --with-new-pkgs
apt-get -y install zulu8-jre-headless
apt-get -y autoremove --purge

adduser --disabled-login --quiet --home /var/lib/minecraft --no-create-home minecraft --gecos ""
mkdir /var/lib/minecraft

# Add mount point for home directory
cat >> /etc/fstab <<EOF
UUID=e0698c68-30d0-482a-9615-a6278be757b4 /var/lib/minecraft ext4 defaults 0 2
EOF
