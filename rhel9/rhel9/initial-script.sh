#!/usr/bin/bash

SERIAL=$(dmidecode -s system-serial-number)
CONFIG=$(grep "^$SERIAL" ./ip_config.csv)
HOST_NAME=$(echo "$CONFIG" | cut -d',' -f2)
BOND1_IP=$(echo "$CONFIG" | cut -d',' -f3)
BOND2_IP=$(echo "$CONFIG" | cut -d',' -f4)
echo "$HOST_NAME $BOND1_IP $BOND2_IP" > /var/log/kickstart-file.log

nmcli connection add type bond con-name bond0 ifname bond0 bond.options "mode=1,miimon=100" 802-3-ethernet.mtu 1500 connection.autoconnect-slaves yes connection.autoconnect yes
nmcli connection add type ethernet slave-type bond con-name bond0-port1 ifname eno1 master bond0 connection.autoconnect yes
nmcli connection add type ethernet slave-type bond con-name bond0-port2 ifname ens3 master bond0 connection.autoconnect yes
nmcli con mod bond0 ipv6.method disabled
nmcli con mod bond0 ipv4.addresses $BOND1_IP ipv4.gateway 10.1.0.1 ipv4.dns "8.8.8.8 8.8.4.4" ipv4.method manual
nmcli con up bond0

nmcli connection add type bond con-name bond1 ifname bond1 bond.options "mode=4,miimon=100,xmit_hash_policy=layer3+4,lacp_rate=1" 802-3-ethernet.mtu 1500 connection.autoconnect-slaves yes connection.autoconnect yes
nmcli connection add type ethernet slave-type bond con-name bond1-port1 ifname eno2 master bond1 connection.autoconnect yes
nmcli connection add type ethernet slave-type bond con-name bond1-port2 ifname ens4 master bond1 connection.autoconnect yes
nmcli con mod bond1 ipv6.method disabled
nmcli con mod bond1 ipv4.addresses $BOND2_IP ipv4.gateway 10.3.209.1 ipv4.dns "172.31.20.10 172.31.20.11" ipv4.method manual
nmcli con up bond1
hostnamectl set-hostname $HOST_NAME
