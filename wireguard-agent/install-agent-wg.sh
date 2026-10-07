#!/usr/bin/env bash
set -euo pipefail

if [[ ${EUID} -ne 0 ]]; then
    printf '%s\n' 'Run this installer as root.' >&2
    exit 1
fi

readonly config=/home/julien/.config/wireguard/freebox-agent.conf
readonly helper=/usr/local/libexec/agent-wg-enter
readonly netns_script=/usr/local/libexec/agent-wg-netns
readonly service=/etc/systemd/system/agent-wg-sandbox.service
readonly sudoers_tmp=/run/agent-wg-sudoers.new
readonly sudoers=/etc/sudoers.d/agent-wg-run
readonly network_config=/etc/agent-wg/network.env
readonly old_service=/etc/systemd/system/agent-vpn-sandbox.service
readonly old_sudoers=/etc/sudoers.d/agent-vpn-run
readonly old_helper=/usr/local/libexec/agent-vpn-enter
readonly old_netns_script=/usr/local/libexec/agent-vpn-netns
readonly repo_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
readonly invoking_user="${SUDO_USER:-}"

[[ "$invoking_user" == 'julien' ]] || {
    printf '%s\n' 'Run this through sudo from Julien’s account.' >&2
    exit 1
}
[[ -r "$config" ]] || {
    printf '%s\n' "Missing private Freebox profile: ${config}" >&2
    exit 1
}
[[ "$(stat -c '%a' "$config")" == '600' ]] || {
    printf '%s\n' 'The Freebox profile must have mode 600.' >&2
    exit 1
}
wg-quick strip "$config" >/dev/null

if systemctl is-active --quiet agent-vpn-sandbox.service; then
    printf '%s\n' 'The old namespace service is active; stop it before renaming the setup.' >&2
    exit 1
fi

install -D -o root -g root -m 0755 \
    "${repo_dir}/agent-wg-netns.sh" "$netns_script"
install -D -o root -g root -m 0644 \
    "${repo_dir}/network.env" "$network_config"
install -D -o root -g root -m 0755 \
    "${repo_dir}/agent-wg-enter" "$helper"
install -D -o root -g root -m 0644 \
    "${repo_dir}/agent-wg-sandbox.service" "$service"

printf '%s ALL=(root) NOPASSWD: %s *\n' "$invoking_user" "$helper" >"$sudoers_tmp"
chmod 0440 "$sudoers_tmp"
visudo -cf "$sudoers_tmp"
install -o root -g root -m 0440 "$sudoers_tmp" "$sudoers"
: >"$sudoers_tmp"

# Retire the previous service name and launcher after the replacement is installed.
systemctl disable agent-vpn-sandbox.service >/dev/null 2>&1 || true
rm -f "$old_service" "$old_sudoers" "$old_helper" "$old_netns_script"
systemctl daemon-reload

printf '%s\n' 'WireGuard sandbox tools installed. The service was not enabled or started.'
printf 'Start only after review with: sudo systemctl start %s\n' 'agent-wg-sandbox.service'
