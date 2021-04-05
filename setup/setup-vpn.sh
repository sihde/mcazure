#!/bin/bash

set -e

# Timezone
ln -sf /usr/share/zoneinfo/America/Los_Angeles /etc/localtime
dpkg-reconfigure -f noninteractive tzdata

# Preseed debconf
echo sysstat sysstat/enable boolean true | debconf-set-selections

# Install and upgrade packages
apt-get update
apt-get -y upgrade --with-new-pkgs
apt-get -y install wireguard nftables
apt-get -y autoremove --purge

cat >> /home/sihde/.ssh/authorized_keys <<EOF
ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIL6bvTJwY3DJT1c2ukmUJMJaLvCQUHpall3zQRjOb/2M sihde@sihde-mn3.linkedin.biz
ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIKutxzLvxoo8rrwBgw/JWkPLewTpEGZDNqpPif7EpGit sihde@toocoo
ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIKqPM2vgeGCz30yywQpUKLBd2PW49v4gsZWdP8WdSEKE sihde@sihde-ld1.linkedin.biz
ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIHkUe9+nsoJNMhPWNXX8qzL9dq6NvcNuK8PvT19rvFrW sihde@DESKTOP-PPRJK48
ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAICLDrdUadTMo+pD0IgDOfDnkWMyamfbRkGcsXqsififK sihde@DESKTOP-IART6IV
ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAICI8eR8jWqi/fCbiXEWijGYbixK0ZdDMuEsBDUR9PgFT sihde@pixel5
EOF

# WireGuard config
mkdir -p /etc/wireguard
umask 0077
wg genkey > /etc/wireguard/wg0.key

cat > /etc/wireguard/wg0.conf <<EOF
# Remember IPv4 depends on nftables NAT configuration
[Interface]
Address = 192.168.96.1/24
PrivateKey = $(cat /etc/wireguard/wg0.key)
ListenPort = 51820
# Fail if NAT rule not installed
PreUp = nft list table ip %i | grep -qF 192.168.96.0/24

# MacBook
[Peer]
PublicKey = ljaDpSqtvP6mlI5Bjw+3BHPsEohhHBQ4UOeKEV9XFiI=
AllowedIPs = 192.168.96.2/32
EOF

systemctl enable wg-quick@wg0.service

cp nftables.conf /etc/nftables.conf

