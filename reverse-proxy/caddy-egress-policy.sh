#!/usr/bin/env bash
set -euo pipefail

readonly gateway="${CADDY_EGRESS_GATEWAY:-192.168.77.1}"
readonly table=200
readonly mark=0x434350
readonly mark_mask=0xffffffff
readonly chain=CADDY_EGRESS
readonly ports=(18080 18443 18765)

fail() {
    printf '%s\n' "$*" >&2
    exit 1
}

require_root() {
    [[ ${EUID} -eq 0 ]] || fail 'Run this policy through its systemd service or as root.'
}

discover_lan() {
    local route_info
    route_info="$(ip -4 route get "$gateway" 2>/dev/null | head -n 1)" || fail "No route to normal gateway ${gateway}."
    lan_interface="$(awk '{ for (i = 1; i <= NF; i++) if ($i == "dev") { print $(i + 1); exit } }' <<<"$route_info")"
    lan_address="$(awk '{ for (i = 1; i <= NF; i++) if ($i == "src") { print $(i + 1); exit } }' <<<"$route_info")"
    lan_prefix="$(ip -4 route show dev "$lan_interface" scope link | awk '$1 ~ /\// { print $1; exit }')"
    [[ -n "$lan_interface" && -n "$lan_address" && -n "$lan_prefix" ]] || fail 'Could not identify the normal LAN interface and subnet.'
}

start_policy() {
    require_root
    discover_lan

    ip -4 route replace table "$table" "$lan_prefix" dev "$lan_interface" scope link src "$lan_address"
    ip -4 route replace table "$table" default via "$gateway" dev "$lan_interface" src "$lan_address"

    if ! ip -4 rule show | grep -Fq "fwmark ${mark}/${mark_mask} lookup ${table}"; then
        ip -4 rule add priority 0 fwmark "${mark}/${mark_mask}" lookup "$table"
    fi

    iptables -w -t mangle -N "$chain" 2>/dev/null || true
    iptables -w -t mangle -F "$chain"
    for port in "${ports[@]}"; do
        iptables -w -t mangle -A "$chain" \
            -i "$lan_interface" -d "$lan_address" -p tcp --dport "$port" \
            -j CONNMARK --set-xmark "${mark}/${mark_mask}"
    done
    iptables -w -t mangle -A "$chain" -j RETURN
    iptables -w -t mangle -C PREROUTING -j "$chain" 2>/dev/null || \
        iptables -w -t mangle -I PREROUTING 1 -j "$chain"
    iptables -w -t mangle -C OUTPUT -p tcp \
        -m connmark --mark "${mark}/${mark_mask}" \
        -j MARK --set-xmark "${mark}/${mark_mask}" 2>/dev/null || \
        iptables -w -t mangle -A OUTPUT -p tcp \
            -m connmark --mark "${mark}/${mark_mask}" \
            -j MARK --set-xmark "${mark}/${mark_mask}"

    local test_route
    test_route="$(ip -4 route get 1.1.1.1 from "$lan_address" mark "$mark")"
    [[ "$test_route" == *"via $gateway dev $lan_interface"* ]] || fail "Caddy return route did not select ${lan_interface}: ${test_route}"
    printf 'Caddy return traffic uses %s via %s; other traffic keeps its existing route.\n' "$lan_interface" "$gateway"
}

show_plan() {
    discover_lan
    printf 'normal_interface=%s\nnormal_address=%s\nnormal_gateway=%s\n' \
        "$lan_interface" "$lan_address" "$gateway"
    printf 'caddy_host_ports=%s\nroute_table=%s\nconnection_mark=%s/%s\n' \
        "${ports[*]}" "$table" "$mark" "$mark_mask"
}

stop_policy() {
    require_root
    iptables -w -t mangle -D PREROUTING -j "$chain" 2>/dev/null || true
    iptables -w -t mangle -D OUTPUT -p tcp \
        -m connmark --mark "${mark}/${mark_mask}" \
        -j MARK --set-xmark "${mark}/${mark_mask}" 2>/dev/null || true
    iptables -w -t mangle -F "$chain" 2>/dev/null || true
    iptables -w -t mangle -X "$chain" 2>/dev/null || true
    ip -4 rule del priority 0 fwmark "${mark}/${mark_mask}" lookup "$table" 2>/dev/null || true
    ip -4 route flush table "$table" 2>/dev/null || true
}

case "${1:-start}" in
    start)
        start_policy
        ;;
    plan)
        show_plan
        ;;
    stop)
        stop_policy
        ;;
    *)
        fail "Usage: $0 {plan|start|stop}"
        ;;
esac
