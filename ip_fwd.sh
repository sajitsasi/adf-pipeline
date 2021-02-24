#!/bin/bash

#-------------------------------------------------------------------------
# Copyright (c) Microsoft Corporation. All rights reserved.
# Licensed under the MIT License. 
#--------------------------------------------------------------------------

usage() {
	echo -e "\e[33m"
	echo "usage: ${0} [-i <eth_interface>] [-f <frontend_port>] [-a <dest_ip_addr>] [-b <dest_port>]" 1>&2
	echo "where:" 1>&2
	echo "<eth_interface>: Interface on which packet will arrive and be forwarded" 1>&2
	echo "<frontend_port>: Frontend port on which packet arrives" 1>&2
	echo "<dest_port>    : Destination port to which packet is forwarded" 1>&2
	echo "<dest_ip_addr> : Destination IP which packet is forwarded" 1>&2
	echo -e "\e[0m"
}

if [[ $# -eq 0 ]]; then
	echo -e "\e[31mERROR: no options given\e[0m"
	usage
	exit 1
fi
while getopts 'i:f:a:b:' OPTS; do
	case "${OPTS}" in
		i)
			echo -e "\e[32mUsing ethernet interface ${OPTARG}\e[0m"
			ETH_IF=${OPTARG}
			;;
		f)
			echo -e "\e[32mFrontend port is ${OPTARG}\e[0m"
			FE_PORT=${OPTARG}
			;;
		a)
			echo -e "\e[32mDestination IP Address is ${OPTARG}\e[0m"
			DEST_HOST=${OPTARG}
			;;
		b)
			echo -e "\e[32mDestination Port is ${OPTARG}\e[0m"
			DEST_PORT=${OPTARG}
			;;
		*)
			usage
			exit 1
			;;
	esac
done

if [ -z ${ETH_IF} ]; then
	echo -e "\e[31mERROR: ethernet interface not specified!!!\e[0m"
	usage
	exit 1
fi
if [ -z ${FE_PORT} ]; then
	echo -e "\e[31mERROR: frontend port not specified!!!\e[0m"
	usage
	exit 1
fi
if [ -z ${DEST_HOST} ]; then
	echo -e "\e[31mERROR: destination IP not specified!!!\e[0m"
	usage
	exit 1
fi
if [ -z ${DEST_PORT} ]; then
	echo -e "\e[31mERROR: destination port not specified!!!\e[0m"
	usage
	exit 1
fi

#1. Make sure you're root
echo -e "\e[32mChecking whether we're root...\e[0m"
if [ -z ${UID} ]; then
	UID=$(id -u)
fi
if [ "${UID}" != "0" ]; then
	echo -e "\e[31mERROR: user must be root\e[0m"
	exit 1
fi

#2. Make sure IP Forwarding is enabled in the kernel
echo -e "\e[32mEnabling IP forwarding...\e[0m"
echo "1" > /proc/sys/net/ipv4/ip_forward

#3. Check if IP or hostname is specified for destination IP
if [[ ${DEST_HOST} =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
	DEST_IP=${DEST_HOST}
else
	DEST_IP=$(host ${DEST_HOST} | grep -v IPv6 | grep "has address" -m 1 | awk '{print $NF}')
fi
echo -e "\e[32mUsing Destination IP ${DEST_IP}\e[0m"

#4. Get local IP
LOCAL_IP=$(ip addr ls ${ETH_IF} | grep -w inet | awk '{print $2}' | awk -F/ '{print $1}')
echo -e "\e[32mUsing Local IP ${LOCAL_IP}\e[0m"

#4. Do DNAT
DNAT_CMD="iptables -t nat -A PREROUTING -p tcp -i ${ETH_IF} --dport ${FE_PORT} -j DNAT --to ${DEST_IP}:${DEST_PORT}"
echo -e "\e[32mCreating DNAT rule from ${LOCAL_IP}:${FE_PORT} to ${DEST_IP}:${DEST_PORT}...\e[0m"
${DNAT_CMD}

#4. Do SNAT
SNAT_CMD="iptables -t nat -A POSTROUTING -p tcp -o ${ETH_IF} --dport ${DEST_PORT} -j SNAT -d ${DEST_IP} --to-source ${LOCAL_IP}:${FE_PORT}"
echo -e "\e[32mCreating SNAT rule from ${DEST_IP}:${DEST_PORT} to ${LOCAL_IP}:${FE_PORT}...\e[0m"
${SNAT_CMD}
#iptables -t nat -A POSTROUTING -o ${ETH_IF} -j MASQUERADE

#5. Save iptables rules
echo -e "\e[32mCreating Saving iptables rules...\e[0m"
/sbin/iptables-save > /etc/iptables/rules.v4

#6. Store information
IP_FWD_DIR="/opt/ip_forward"
mkdir -p ${IP_FWD_DIR}
DNAT_DEL_CMD=$(echo ${DNAT_CMD} | sed -e 's/\-A/\-D/g')
SNAT_DEL_CMD=$(echo ${SNAT_CMD} | sed -e 's/\-A/\-D/g')
EPOCH=$(date +%s)
echo ${DNAT_DEL_CMD} > ${IP_FWD_DIR}/"${EPOCH}_${FE_PORT}"
echo ${SNAT_DEL_CMD} >> ${IP_FWD_DIR}/"${EPOCH}_${FE_PORT}"
echo "${EPOCH} ${FE_PORT}" >> ${IP_FWD_DIR}/.history
echo -e "\e[32m\n\nTo delete the created rule, from az cli run the following:\n\n\e[0m"
echo -e "\e[33maz vm run-command invoke --command-id RunShellScript -g <resource_group> -n <vm_name> --scripts \"${DNAT_DEL_CMD}\"\e[0m"
echo -e "\e[33maz vm run-command invoke --command-id RunShellScript -g <resource_group> -n <vm_name> --scripts \"${SNAT_DEL_CMD}\"\e[0m"
echo -e "\e[32m\n\nSubstitute appropriate values for <resource_group> and <vm_name>\e[0m]"
echo -e "\e[32mDone\e[0m"
