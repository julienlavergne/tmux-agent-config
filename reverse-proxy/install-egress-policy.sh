#!/usr/bin/env bash
set -euo pipefail

if [[ ${EUID} -ne 0 ]]; then
    printf '%s\n' 'Run this installer as root.' >&2
    exit 1
fi

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
install -D -o root -g root -m 0755 \
    "${script_dir}/caddy-egress-policy.sh" \
    /usr/local/libexec/caddy-egress-policy
install -D -o root -g root -m 0644 \
    "${script_dir}/caddy-egress-policy.service" \
    /etc/systemd/system/caddy-egress-policy.service
systemctl daemon-reload
systemctl enable --now caddy-egress-policy.service
