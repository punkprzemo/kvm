#!/bin/bash

if ! [ $# -eq 3 ]; then
    echo "Usage: $0 <node_name> <how_many_disks> <disk_size>"
    exit 1
fi


NODE=$1
NUMDISK=$2
SIZE=$3
for i in `seq 1 $NUMDISK`
do
	qemu-img create -f qcow2 /var/lib/libvirt/images/$NODE/$NODE-disk$i.qcow2 $SIZE
done

declare -a disk=( vda vdb vdc vdd vde vdf vdg vdh vdi vdj vdk)


for i in `seq 1 $NUMDISK`
do
	virsh attach-disk $NODE /var/lib/libvirt/images/$NODE/$NODE-disk$i.qcow2 --target ${disk[$i]} --driver qemu --subdriver qcow2 --targetbus virtio --persistent
done
