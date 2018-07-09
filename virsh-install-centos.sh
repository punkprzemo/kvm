#!/bin/bash

## **Updates to this file are now at https://github.com/giovtorres/kvm-install-vm.**
## **This updated version has more options and less hardcoded variables.**

# Take one argument from the commandline: VM name
if ! [ $# -eq 4 ]; then
    echo "Usage: $0 <node_name> <image_name> <memory_size> <cpus_num>"
    exit 1
fi

# Check if domain already exists
virsh dominfo $1 > /dev/null 2>&1
if [ "$?" -eq 0 ]; then
    echo -n "[WARNING] $1 already exists.  "
    read -p "Do you want to overwrite $1 (y/[N])? " -r
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        echo ""
        virsh destroy $1 > /dev/null
        virsh undefine $1 > /dev/null
    else
        echo -e "\nNot overwriting $1. Exiting..."
        exit 1
    fi
fi

# Directory to store images
DIR=/var/lib/libvirt/images

# Location of cloud image
IMAGE=$DIR/CentOS-7-x86_64-GenericCloud.qcow2
if [ -n "$2" ]
then
IMAGE=$DIR/$2
fi
# Amount of RAM in MB
MEM=1536
if [ -n "$3" ]
then
MEM=$3
fi
# Number of virtual CPUs
CPUS=1
if [ -n "$4" ]
then
CPUS=$4
fi
# Cloud init files
USER_DATA=user-data
META_DATA=meta-data
CI_ISO=$1-cidata.iso
DISK=$1_linked_disk1.qcow2

# Bridge for VMs (default on Fedora is virbr0)
BRIDGE=virbr0

# Start clean
rm -rf $DIR/$1
mkdir -p $DIR/$1

pushd $DIR/$1 > /dev/null

    # Create log file
    touch $1.log

    echo "$(date -R) Destroying the $1 domain (if it exists)..."

    # Remove domain with the same name
    virsh destroy $1 >> $1.log 2>&1
    virsh undefine $1 >> $1.log 2>&1

    # cloud-init config: set hostname, remove cloud-init package,
    # and add ssh-key 
    cat > $USER_DATA << _EOF_
#cloud-config
# Hostname management
preserve_hostname: False
hostname: $1
fqdn: $1.lab.example.com
# Manage resolv.conf
manage_resolv_conf: true
resolv_conf:
  nameservers: ['192.168.122.1']
  searchdomains:
    - lab.example.com
  domain: example.com
  options:
    rotate: true
    timeout: 1

# Remove cloud-init when finished with it
runcmd:
  - [ yum, -y, remove, cloud-init ]
# Configure where output will go
output: 
  all: ">> /var/log/cloud-init.log"
# configure interaction with ssh server
ssh_svcname: ssh
ssh_deletekeys: True
ssh_genkeytypes: ['rsa', 'ecdsa']
# Install my public ssh key to the first user-defined user configured 
# in cloud.cfg in the template (which is centos for CentOS cloud images)
ssh_authorized_keys:
  - ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABAQC8/6Wpeqx/KD/qKc3HHs5+6RdCUmV69IEwi59O+7+OxgWqnsOFvDmVVt0NgJbmmE34P96Z3hSYxlVQeuzlmGLuP+VBpZLXwj8Fk048NkyAkROpODLcTGRjjvGCEUkfCRVXveaRBSfx545vUmk5/TMpGRe7epB4I0YruqR5HT0MV/lYY/uHh8SgM5gPzavdruDPOdzE4CuznT3kusu6nqT/J31CjrdEdAOf5FpLK5DMSHiHznjyAhH/GyVDS9s9DdZ8oMjz6gAC7ZlS1yP+SXb1QNIYnCjLMnGc/DKyPcJ/16FQ3ofh+oh2WTPv33v+dTIoRQawdfDZlfGLoU6QivT9 root@master
_EOF_

    echo "instance-id: $1; local-hostname: $1" > $META_DATA

    echo "$(date -R) Copying template image..."
#    cp $IMAGE ${IMAGE}-copy
#    chown qemu:qemu ${IMAGE}-copy
    qemu-img create -f qcow2 -b $IMAGE $DISK
    # Create CD-ROM ISO with cloud-init config
    echo "$(date -R) Generating ISO for cloud-init..."
    genisoimage -output $CI_ISO -volid cidata -joliet -r $USER_DATA $META_DATA &>> $1.log

    echo "$(date -R) Installing the domain and adjusting the configuration..."
    echo "[INFO] Installing with the following parameters:"
    echo "virt-install --import --name $1 --ram $MEM --vcpus $CPUS --disk
    $DISK,format=qcow2,bus=virtio,size=8G --disk $CI_ISO,device=cdrom --network
    bridge=virbr0,model=virtio --os-type=linux --os-variant=rhel7.5 --noautoconsole"

    virt-install --import --name $1 --ram $MEM --vcpus $CPUS --disk \
    $DISK,format=qcow2,bus=virtio --disk $CI_ISO,device=cdrom --network \
    bridge=virbr0,model=virtio --os-type=linux --os-variant=rhel7.5 --noautoconsole

    MAC=$(virsh dumpxml $1 | awk -F\' '/mac address/ {print $2}')
    while true
    do
        IP=$(grep -B1 $MAC /var/lib/libvirt/dnsmasq/$BRIDGE.status | head \
             -n 1 | awk '{print $2}' | sed -e s/\"//g -e s/,//)
        if [ "$IP" = "" ]
        then
            sleep 1
        else
            break
        fi
    done

    # Eject cdrom
    echo "$(date -R) Cleaning up cloud-init..."
    virsh change-media $1 hda --eject --config >> $1.log

    # Remove the unnecessary cloud init files
    rm $USER_DATA $CI_ISO
    #add new host entry in /etc/hosts
    if grep -q "^$IP $1.lab.example.com $1" /etc/hosts
    then
    	echo "already exists"
    else
	echo "$IP $1.lab.example.com $1" >> /etc/hosts
    fi

    echo "$(date -R) DONE. SSH to $1 using $IP with  username 'centos'."

popd > /dev/null
