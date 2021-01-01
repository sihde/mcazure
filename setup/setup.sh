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
