#!/bin/bash

NODE=$1

virsh destroy $NODE
virsh snapshot-delete --current --domain $NODE
virsh undefine $NODE
virsh pool-delete --pool $NODE
rm -rf /var/lib/libvirt/images/$NODE
sed  -i "/$NODE/d" /etc/hosts
