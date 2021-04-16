#!/bin/bash

set -euxo pipefail

export FARCASTER_PATH=/farcaster
export PATH="${FARCASTER_PATH}"/sbin:"${FARCASTER_PATH}"/bin:${PATH}

. "${FARCASTER_PATH}/bin/_lib.sh"
. "${FARCASTER_PATH}/bin/_env.sh"

# Firewall and NAT rules
iptables -N FARCASTER-FILTER
iptables -A FARCASTER-FILTER -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT
iptables -A FARCASTER-FILTER -p icmp --fragment -j DROP
iptables -A FARCASTER-FILTER -p icmp --icmp-type 3/4 -m conntrack \
	--ctstate ESTABLISHED,RELATED -j ACCEPT
iptables -A FARCASTER-FILTER -p icmp --icmp-type 4 -m conntrack \
	--ctstate ESTABLISHED,RELATED -j ACCEPT
iptables -A FARCASTER-FILTER -p icmp --icmp-type 8 -j ACCEPT

iptables -F INPUT
iptables -P INPUT DROP
iptables -A INPUT -j FARCASTER-FILTER
iptables -A INPUT -i lo -j ACCEPT
iptables -A INPUT -i "${WG_TUN_IF}" -p udp --dport ${WG_DEFAULT_PORT} -j ACCEPT

iptables -F FORWARD
iptables -P FORWARD DROP
iptables -A FORWARD -j FARCASTER-FILTER
iptables -A FORWARD -i "${WG_GW_IF}" -j ACCEPT

iptables -t nat -N FARCASTER-NAT
iptables -t nat -A FARCASTER-NAT -o "${WG_TUN_IF}" -j RETURN
iptables -t nat -A FARCASTER-NAT -o "${WG_GW_IF}" -j RETURN
iptables -t nat -A FARCASTER-NAT -j MASQUERADE
iptables -t nat -F POSTROUTING
iptables -t nat -A POSTROUTING -j FARCASTER-NAT

# Redirect any DNS request to a local dnsmasq and let it handle the details
rundir=/run/dnsmasq
lport=1053
mkdir -p ${rundir}
chown -R root:root ${rundir}
chmod 0711 ${rundir}
dnsmasq -x ${rundir}/dnsmasq.pid -p "${lport}" -i "${WG_GW_IF}"
gw_addr="$(get_wg_addr "${WG_GW_IF}")"
for proto in tcp udp; do
	iptables -t nat -I PREROUTING -i "${WG_GW_IF}" -p ${proto} \
		--dport 53 -j DNAT --to-destination "${gw_addr}:${lport}"
	iptables -t filter -I INPUT -i "${WG_GW_IF}" -p ${proto} \
		-d "${gw_addr}" --dport "${lport}" -j ACCEPT
done

rc=1
if start_wireguard "${WG_GW_IF}"; then
    set +x
    check_hub=0
    rc=$(watch_wireguard "${WG_GW_IF}" ${check_hub})
fi
sleep 5
exit ${rc}
