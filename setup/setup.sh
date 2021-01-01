#!/bin/bash

set -e

cp zulu.list /etc/apt/sources.list.d/zulu.list
cp zulu /etc/apt/preferences.d/zulu
mkdir -p /usr/local/share/keyrings
cp RPM-GPG-KEY-azulsystems /usr/local/share/keyrings

apt update
apt install zulu8-jre-headless

