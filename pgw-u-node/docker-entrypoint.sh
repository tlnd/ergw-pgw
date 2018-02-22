#!/bin/bash

# exit with message
exit_msg () {
	echo $1
	exit 1
}

# creates erlang notation of ip address without netmask
# 192.168.10.1/24 -> 192,168,10,1
ip_to_erlang() {
	echo $1 | sed 's/\./,/g' - | sed 's/\/.*$//g' - | sed 's/.*/{\0}/g' -
}

# creates erlang notation of network
# 192.168.10.1/24 -> {192, 168, 10, 1}, 24
net_to_erlang() {
	echo $1 | sed -e 's/\([0-9]\{1,3\}\)\.\([0-9]\{1,3\}\)\.\([0-9]\{1,3\}\)\.\([0-9]\{1,3\}\)\/\([0-9]\{1,2\}\)/{\1, \2, \3, \4}, \5/' - | sed 's/.*/{\0}/g' -
}


parse_generic () {
	#echo parsing ${1}=${!1}
	[ -n "${!1}" ] || ( echo "env variable $1 is not set"; false )
}

parse_ip_net () {
	#TODO: some more validation for IP networks
	parse_generic $1 && eval export ${1}_ERL=\"$(net_to_erlang ${!1})\"
}

parse_ip_addr () {
	#TODO: some more validation for IP addresses
	parse_generic $1 && eval export ${1}_ERL=\"$(ip_to_erlang ${!1})\"
}

VALIDATION_ERROR=""

parse_ip_addr PGW_S5U_IPADDR || VALIDATION_ERROR=1
parse_generic PGW_S5U_IPADDR_PREFIX_LEN || VALIDATION_ERROR=1
parse_generic PGW_S5U_IFACE || VALIDATION_ERROR=1
parse_ip_net PGW_CLIENT_IP_NET || VALIDATION_ERROR=1

parse_ip_addr PGW_SGI_IPADDR || VALIDATION_ERROR=1
parse_generic PGW_SGI_IPADDR_PREFIX_LEN || VALIDATION_ERROR=1
parse_generic PGW_SGI_IFACE || VALIDATION_ERROR=1
parse_ip_addr PGW_SGI_GW || VALIDATION_ERROR=1

[ -n "$VALIDATION_ERROR" ] && exit_msg "Exiting due to missing configuration parameters"

# create the config from template
envsubst < /config/pgw-u-node.config.templ > /etc/ergw-gtp-u-node/ergw-gtp-u-node.config

# unload gtp module as reset; will be reloaded on start of application
#rmmod gtp

# Setup VRFs
ifup() {
    /sbin/ip link add $1 type vrf table $2
    /sbin/ip link set dev $1 up
    /sbin/ip rule add oif $1 table $2
    /sbin/ip rule add iif $1 table $2

    /sbin/ip link set dev $3 master $1
    /sbin/ip link set dev $3 up
    /sbin/ip addr flush dev $3
    /sbin/ip addr add $4 dev $3
    /sbin/ip route add table $2 default via $5
}

ifup upstream 10 $PGW_SGI_IFACE $PGW_SGI_IPADDR/$PGW_SGI_IPADDR_PREFIX_LEN $PGW_SGI_GW
ifup grx 20 $PGW_S5U_IFACE $PGW_S5U_IPADDR/$PGW_S5U_IPADDR_PREFIX_LEN $PGW_S5U_GW

[ -n "$PGW_SGI_MASQ" ] && iptables -t nat -A POSTROUTING -o $PGW_SGI_IFACE -j MASQUERADE

[ -n "$PGW_SET_TCP_MSS" ] && iptables -t mangle -A FORWARD -p tcp --tcp-flags SYN,RST SYN -j TCPMSS --set-mss $PGW_SET_TCP_MSS


exec "$@"
