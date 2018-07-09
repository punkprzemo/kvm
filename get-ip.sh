#!/bin/bash

NODENAME=$1

NODEMAC=$(virsh domiflist $NODENAME | grep -o ..:..:..:..:..:..)

arp | grep ${NODEMAC} | cut -f1 -d" "
