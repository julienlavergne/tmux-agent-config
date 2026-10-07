#!/usr/bin/env bash
set -euo pipefail

readonly namespace='agent-wg'
readonly interface='wg-agent'
readonly config='/home/julien/.config/wireguard/freebox-agent.conf'
readonly state_file='/run/agent-wg-netns.state'
readonly underlay_interface='eth3'
readonly network_config='/etc/agent-wg/network.env'

[[ -r "$network_config" ]] || {
    printf 'Missing namespace network configuration: %s\n' "$network_config" >&2
    exit 1
}
# shellcheck source=/etc/agent-wg/network.env
source "$network_config"

readonly caddy_bridge="${AGENT_WG_CADDY_BRIDGE:?}"
readonly host_veth="${AGENT_WG_HOST_VETH:?}"
readonly namespace_veth="${AGENT_WG_NAMESPACE_VETH:?}"
readonly host_veth_address="${AGENT_WG_HOST_VETH_IP:?}"
readonly namespace_veth_address="${BRIDGE_HOST:?}"
readonly namespace_veth_cidr="${BRIDGE_HOST}/${AGENT_WG_VETH_PREFIX:?}"
readonly bridge_port="${BRIDGE_PORT:?}"

fail() {
    printf '%s\n' "$*" >&2
    exit 1
}

require_root() {
    [[ ${EUID} -eq 0 ]] || fail 'Run this through agent-wg-sandbox.service or as root.'
}

config_value() {
    local wanted_section="$1"
    local wanted_key="$2"
    awk -F= -v wanted_section="$wanted_section" -v wanted_key="$wanted_key" '
        /^\[/ {
            section = $0
            gsub(/[\[\]]/, "", section)
            next
        }
        section == wanted_section {
            key = $1
            gsub(/^[[:space:]]+|[[:space:]]+$/, "", key)
            if (key == wanted_key) {
                value = substr($0, index($0, "=") + 1)
                gsub(/^[[:space:]]+|[[:space:]]+$/, "", value)
                print value
                exit
            }
        }
    ' "$config"
}

validate_config() {
    [[ -r "$config" ]] || fail "Missing Freebox client profile: ${config}"
    [[ "$(stat -c '%a' "$config")" == '600' ]] || fail 'The Freebox profile must have mode 600.'
    wg-quick strip "$config" >/dev/null || fail 'The Freebox profile could not be parsed.'

    client_addresses="$(config_value Interface Address)"
    dns_servers="$(config_value Interface DNS)"
    allowed_ips="$(config_value Peer AllowedIPs | tr -d '[:space:]')"
    endpoint="$(config_value Peer Endpoint)"

    [[ -n "$client_addresses" ]] || fail 'The Freebox profile has no client address.'
    [[ -n "$dns_servers" ]] || fail 'The Freebox profile has no DNS server.'
    [[ ",$allowed_ips," == *',0.0.0.0/0,'* ]] || fail 'Expected a full IPv4 tunnel (AllowedIPs must include 0.0.0.0/0).'
    [[ "$endpoint" =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}:[0-9]+$ ]] || \
        fail 'This setup expects the Freebox profile to contain an IPv4 endpoint address and port.'
    endpoint_ip="${endpoint%:*}"
    ip -4 route get "$endpoint_ip" >/dev/null 2>&1 || fail 'The Freebox endpoint is not reachable through the current network.'
}

normal_route() {
    local route gateway_route
    route="$(ip -4 route show default dev "$underlay_interface" | head -n 1)"
    [[ -n "$route" ]] || fail "No normal-network default route on ${underlay_interface}."
    underlay_gateway="$(awk '{ for (i = 1; i <= NF; i++) if ($i == "via") { print $(i + 1); exit } }' <<<"$route")"
    [[ -n "$underlay_gateway" ]] || fail "Could not identify the normal gateway on ${underlay_interface}."
    gateway_route="$(ip -4 route get "$underlay_gateway")"
    underlay_address="$(awk '{ for (i = 1; i <= NF; i++) if ($i == "src") { print $(i + 1); exit } }' <<<"$gateway_route")"
    [[ -n "$underlay_gateway" && -n "$underlay_address" ]] || fail "Could not determine the normal gateway and address on ${underlay_interface}."
}

install_bridge_forwarding_rules() {
    iptables -w -C INPUT -i "$host_veth" -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT 2>/dev/null || \
        iptables -w -I INPUT 1 -i "$host_veth" -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT
    iptables -w -C INPUT -i "$host_veth" -j DROP 2>/dev/null || \
        iptables -w -I INPUT 2 -i "$host_veth" -j DROP

    iptables -w -C FORWARD -i "$caddy_bridge" -o "$host_veth" \
        -d "${namespace_veth_address}/32" -p tcp --dport "$bridge_port" \
        -m conntrack --ctstate NEW,ESTABLISHED -j ACCEPT 2>/dev/null || \
        iptables -w -I FORWARD 1 -i "$caddy_bridge" -o "$host_veth" \
            -d "${namespace_veth_address}/32" -p tcp --dport "$bridge_port" \
            -m conntrack --ctstate NEW,ESTABLISHED -j ACCEPT
    iptables -w -C FORWARD -i "$host_veth" -o "$caddy_bridge" \
        -s "${namespace_veth_address}/32" -p tcp --sport "$bridge_port" \
        -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT 2>/dev/null || \
        iptables -w -I FORWARD 1 -i "$host_veth" -o "$caddy_bridge" \
            -s "${namespace_veth_address}/32" -p tcp --sport "$bridge_port" \
            -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT
    iptables -w -t nat -C POSTROUTING -o "$host_veth" \
        -d "${namespace_veth_address}/32" -p tcp --dport "$bridge_port" \
        -j SNAT --to-source "$host_veth_address" 2>/dev/null || \
        iptables -w -t nat -I POSTROUTING 1 -o "$host_veth" \
            -d "${namespace_veth_address}/32" -p tcp --dport "$bridge_port" \
            -j SNAT --to-source "$host_veth_address"
}

remove_bridge_forwarding_rules() {
    iptables -w -D INPUT -i "$host_veth" -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT 2>/dev/null || true
    iptables -w -D INPUT -i "$host_veth" -j DROP 2>/dev/null || true
    iptables -w -D FORWARD -i "$caddy_bridge" -o "$host_veth" \
        -d "${namespace_veth_address}/32" -p tcp --dport "$bridge_port" \
        -m conntrack --ctstate NEW,ESTABLISHED -j ACCEPT 2>/dev/null || true
    iptables -w -D FORWARD -i "$host_veth" -o "$caddy_bridge" \
        -s "${namespace_veth_address}/32" -p tcp --sport "$bridge_port" \
        -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT 2>/dev/null || true
    iptables -w -t nat -D POSTROUTING -o "$host_veth" \
        -d "${namespace_veth_address}/32" -p tcp --dport "$bridge_port" \
        -j SNAT --to-source "$host_veth_address" 2>/dev/null || true
}

up() {
    require_root
    validate_config
    normal_route

    if ip netns list | awk '{print $1}' | grep -Fxq "$namespace"; then
        fail "The ${namespace} namespace already exists."
    fi

    ip link show dev "$caddy_bridge" >/dev/null 2>&1 || fail "Docker's ${caddy_bridge} interface is unavailable."
    command -v iptables >/dev/null 2>&1 || fail 'iptables is required for the restricted Caddy forwarding path.'

    local endpoint_route_before route_added=0 namespace_created=0 interface_created=0 veth_created=0
    endpoint_route_before="$(ip -4 route get "$endpoint_ip" 2>/dev/null || true)"
    if [[ "$endpoint_route_before" != *"dev ${underlay_interface}"* ]]; then
        ip -4 route add "${endpoint_ip}/32" \
            via "$underlay_gateway" dev "$underlay_interface" src "$underlay_address" metric 1
        route_added=1
    fi

    rollback() {
        remove_bridge_forwarding_rules
        if [[ "$namespace_created" == 1 ]]; then
            ip netns del "$namespace" 2>/dev/null || true
        fi
        if [[ "$veth_created" == 1 ]]; then
            ip link del "$host_veth" 2>/dev/null || true
        fi
        if [[ "$interface_created" == 1 ]]; then
            ip link del "$interface" 2>/dev/null || true
        fi
        if [[ "$route_added" == 1 ]]; then
            ip -4 route del "${endpoint_ip}/32" \
                via "$underlay_gateway" dev "$underlay_interface" src "$underlay_address" metric 1 \
                2>/dev/null || true
        fi
        : > "$state_file"
    }
    trap rollback ERR

    modprobe wireguard
    ip netns add "$namespace"
    namespace_created=1

    ip link add "$host_veth" type veth peer name "$namespace_veth"
    veth_created=1
    ip link set "$namespace_veth" netns "$namespace"
    ip address add "${host_veth_address}/30" dev "$host_veth"
    ip link set "$host_veth" up
    ip -n "$namespace" address add "$namespace_veth_cidr" dev "$namespace_veth"
    ip -n "$namespace" link set "$namespace_veth" up
    install_bridge_forwarding_rules

    ip link add dev "$interface" type wireguard
    interface_created=1
    wg setconf "$interface" <(wg-quick strip "$config")
    ip link set "$interface" netns "$namespace"
    interface_created=0

    mkdir -p "/etc/netns/${namespace}"
    : > "/etc/netns/${namespace}/resolv.conf"
    local dns_server
    IFS=',' read -r -a dns_array <<<"$dns_servers"
    for dns_server in "${dns_array[@]}"; do
        dns_server="${dns_server//[[:space:]]/}"
        [[ -n "$dns_server" ]] && printf 'nameserver %s\n' "$dns_server" >>"/etc/netns/${namespace}/resolv.conf"
    done
    chmod 0644 "/etc/netns/${namespace}/resolv.conf"

    local address
    IFS=',' read -r -a address_array <<<"$client_addresses"
    for address in "${address_array[@]}"; do
        address="${address//[[:space:]]/}"
        [[ -n "$address" ]] && ip -n "$namespace" address add "$address" dev "$interface"
    done
    ip -n "$namespace" link set lo up
    ip -n "$namespace" link set "$interface" up
    ip -n "$namespace" route add default dev "$interface"

    printf 'endpoint=%s\ngateway=%s\ninterface=%s\naddress=%s\nroute_added=%s\n' \
        "$endpoint_ip" "$underlay_gateway" "$underlay_interface" "$underlay_address" "$route_added" >"$state_file"
    chmod 0600 "$state_file"

    local selected_route
    selected_route="$(ip -n "$namespace" -4 route get 1.1.1.1)"
    [[ "$selected_route" == *"dev ${interface}"* ]] || fail "Sandbox route did not select ${interface}: ${selected_route}"
    trap - ERR
    printf 'Namespace %s is configured. Agent IPv4 traffic will use WireGuard; the tunnel is now active.\n' "$namespace"
}

down() {
    require_root
    if ! ip netns list | awk '{print $1}' | grep -Fxq "$namespace"; then
        printf 'Namespace %s is already down.\n' "$namespace"
        return
    fi

    local processes
    processes="$(ip netns pids "$namespace")"
    [[ -z "$processes" ]] || fail "Stop the sandboxed agent processes before stopping the tunnel (PIDs: ${processes//$'\n'/ })."

    remove_bridge_forwarding_rules
    ip netns del "$namespace"
    ip link del "$host_veth" 2>/dev/null || true
    if [[ -s "$state_file" ]]; then
        local endpoint gateway iface address route_added
        endpoint="$(awk -F= '$1 == "endpoint" {print $2}' "$state_file")"
        gateway="$(awk -F= '$1 == "gateway" {print $2}' "$state_file")"
        iface="$(awk -F= '$1 == "interface" {print $2}' "$state_file")"
        address="$(awk -F= '$1 == "address" {print $2}' "$state_file")"
        route_added="$(awk -F= '$1 == "route_added" {print $2}' "$state_file")"
        if [[ "$route_added" == 1 ]]; then
            ip -4 route del "${endpoint}/32" via "$gateway" dev "$iface" src "$address" metric 1
        fi
        : > "$state_file"
    fi
    printf 'Namespace %s is down.\n' "$namespace"
}

status() {
    if ip netns list | awk '{print $1}' | grep -Fxq "$namespace"; then
        ip -n "$namespace" -brief address show
        ip -n "$namespace" -4 route show
        ip -brief address show dev "$host_veth" 2>/dev/null || true
    else
        printf 'Namespace %s is down.\n' "$namespace"
    fi
}

case "${1:-}" in
    up) up ;;
    down) down ;;
    status) status ;;
    check)
        validate_config
        normal_route
        printf 'Profile is valid; full IPv4 tunnel; WireGuard tools are installed; underlay is %s via %s.\n' \
            "$underlay_interface" "$underlay_gateway"
        ;;
    *) fail "Usage: $0 {check|up|down|status}" ;;
esac
