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
apt-get -y install wireguard nftables jq
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

hostname=$(curl -s -H Metadata:true http://169.254.169.254/metadata/instance?api-version=2021-02-01 | jq -r '.compute.osProfile.computerName+"."+.compute.location').cloudapp.azure.com
port=51820

cat > /etc/wireguard/wg0.conf <<EOF
# Remember IPv4 depends on nftables NAT configuration
[Interface]
Address = 192.168.96.1/24
PrivateKey = $(cat /etc/wireguard/wg0.key)
ListenPort = ${port}
# Fail if NAT rule not installed
PreUp = nft list table ip %i | grep -qF 192.168.96.0/24
EOF

addr=1
for client in MacBook Pixel; do
    wg genkey > /etc/wireguard/${client}.key
    ((addr++))
    address=192.168.96.${addr}
    cat >> /etc/wireguard/wg0.conf <<EOF

# ${client}
[Peer]
PublicKey = $(wg pubkey < /etc/wireguard/${client}.key)
AllowedIPs = ${address}/32
EOF

    cat > /etc/wireguard/${client}.conf <<EOF
[Interface]
PrivateKey = $(cat /etc/wireguard/${client}.key)
Address = ${address}/24
DNS = 168.63.129.16

[Peer]
PublicKey = $(wg pubkey < /etc/wireguard/wg0.key)
AllowedIPs = 0.0.0.0/0
Endpoint = ${hostname}:${port}
EOF
done

echo 'net.ipv4.ip_forward=1' > /etc/sysctl.d/50-ipforward.conf
systemctl restart systemd-sysctl.service

cp nftables.conf /etc/nftables.conf
systemctl enable nftables.service
systemctl start nftables.service

systemctl enable wg-quick@wg0.service
systemctl start wg-quick@wg0.service
