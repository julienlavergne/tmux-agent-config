#!/usr/bin/env bash
set -Eeuo pipefail

readonly repo_dir="$(cd -- "$(dirname -- "$(readlink -f -- "${BASH_SOURCE[0]}")")/.." && pwd)"
readonly profile_repo="${repo_dir}/ai-sessions/profiles/desktop/desktop-home-codex.env"
readonly profile_live="${HOME}/.config/ai-sessions/desktop-home-codex.env"
readonly session_unit='ai-session@desktop-home-codex.service'
readonly namespace='agent-wg'
readonly root_unit='agent-wg-sandbox.service'

profile_switched=0
root_started=0

require_user() {
    [[ "$(id -un)" == 'julien' ]] || { echo 'Run this as julien.' >&2; exit 1; }
    export XDG_RUNTIME_DIR="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}"
    export DBUS_SESSION_BUS_ADDRESS="${DBUS_SESSION_BUS_ADDRESS:-unix:path=${XDG_RUNTIME_DIR}/bus}"
    [[ -S "${XDG_RUNTIME_DIR}/bus" ]] || { echo 'The julien systemd user bus is unavailable.' >&2; exit 1; }
    if [[ -n "${TMUX:-}" ]] && [[ "$(tmux display-message -p '#S' 2>/dev/null || true)" == 'desktop-home-codex' ]]; then
        echo 'Run this from a separate terminal; it restarts desktop-home-codex.' >&2
        exit 1
    fi
}

set_profile() {
    python3 - "$profile_repo" "$profile_live" "$1" <<'PY'
from pathlib import Path
import sys

for filename in sys.argv[1:3]:
    path = Path(filename)
    lines = [line for line in path.read_text().splitlines()
             if not line.startswith("NETWORK_NAMESPACE=")]
    lines.append(f"NETWORK_NAMESPACE={sys.argv[3]}")
    path.write_text("\n".join(lines) + "\n")
PY
}

codex_pid_in_namespace() {
    local pids pid args session_id
    pids="$(sudo ip netns pids "$namespace" 2>/dev/null || true)"
    session_id="$(cat "${HOME}/.local/state/ai-sessions/desktop-home-codex.codex-id" 2>/dev/null || true)"
    while IFS= read -r pid; do
        [[ -n "$pid" ]] || continue
        args="$(ps -p "$pid" -o args= 2>/dev/null || true)"
        [[ "$args" == *'codex resume '* && "$args" == *'-C /home/julien'* ]] || continue
        [[ -z "$session_id" || "$args" == *"resume ${session_id} "* ]] || continue
        printf '%s\n' "$pid"
        return 0
    done <<<"$pids"
    return 1
}

recover_worker() {
    set_profile host
    systemctl --user restart "$session_unit" || true
    sudo systemctl disable --now "$root_unit" >/dev/null 2>&1 || true
    printf '%s\n' 'desktop-home-codex is back on the host.'
}

activation_error() {
    local status="$1" line="$2" command="$3"
    trap - ERR
    printf '\nActivation failed at line %s: %s\n' "$line" "$command" >&2
    if [[ "$profile_switched" == 1 ]]; then
        echo 'Restoring desktop-home-codex to the host.' >&2
        recover_worker || echo 'Recovery failed; run agent-wg-transition recover from a separate terminal.' >&2
    elif [[ "$root_started" == 1 ]]; then
        sudo systemctl disable --now "$root_unit" >/dev/null 2>&1 || true
    fi
    exit "$status"
}

activate() {
    trap 'activation_error "$?" "$LINENO" "$BASH_COMMAND"' ERR
    require_user
    sudo -v
    [[ -r "${HOME}/.config/wireguard/freebox-agent.conf" ]] || { echo 'The Freebox WireGuard profile is missing.' >&2; return 1; }
    cmp -s "${repo_dir}/wireguard-agent/network.env" /etc/agent-wg/network.env || {
        echo 'The installed network.env differs; rerun install-agent-wg.sh.' >&2; return 1;
    }
    ip -4 route show default dev eth3 | grep -q . || { echo 'The WSL LAN route on eth3 is missing.' >&2; return 1; }

    echo 'Starting agent-wg and checking its WireGuard egress...'
    if ! sudo systemctl is-active --quiet "$root_unit"; then
        root_started=1
    fi
    sudo systemctl enable --now "$root_unit"
    local egress_ip='' handshake
    for ((attempt = 1; attempt <= 8; attempt++)); do
        egress_ip="$("${HOME}/.local/bin/agent-wg-run" -- /usr/bin/curl -4 -fsS --max-time 8 https://api.ipify.org 2>/dev/null || true)"
        [[ "$egress_ip" =~ ^[0-9]{1,3}(\.[0-9]{1,3}){3}$ ]] && break
        sleep 1
    done
    [[ "$egress_ip" =~ ^[0-9]{1,3}(\.[0-9]{1,3}){3}$ ]] || { echo 'No IPv4 egress through agent-wg.' >&2; return 1; }
    handshake="$(sudo ip netns exec "$namespace" wg show wg-agent latest-handshakes | awk 'NR == 1 {print $2}')"
    [[ "${handshake:-0}" =~ ^[1-9][0-9]*$ ]] || { echo 'WireGuard did not complete a handshake.' >&2; return 1; }
    printf 'WireGuard is up; sandbox egress is %s.\n' "$egress_ip"

    profile_switched=1
    set_profile "$namespace"
    systemctl --user restart "$session_unit"

    local pid
    for ((attempt = 1; attempt <= 90; attempt++)); do
        pid="$(codex_pid_in_namespace || true)"
        if [[ -n "$pid" ]]; then
            systemctl --user is-active --quiet "$session_unit"
            echo "desktop-home-codex is running in ${namespace} (Codex PID ${pid})."
            trap - ERR
            return 0
        fi
        sleep 1
    done
    echo 'desktop-home-codex did not start in agent-wg within 90 seconds.' >&2
    return 1
}

status() {
    sudo systemctl is-active "$root_unit" 2>/dev/null || true
    sudo ip netns list 2>/dev/null || true
    systemctl --user is-active "$session_unit" 2>/dev/null || true
    if [[ -r "$profile_live" ]]; then
        sed -n 's/^NETWORK_NAMESPACE=/NETWORK_NAMESPACE=/p' "$profile_live"
    fi
}

case "${1:-}" in
    activate) activate ;;
    recover) require_user; sudo -v; recover_worker ;;
    status) status ;;
    *) echo 'Usage: agent-wg-transition {activate|recover|status}' >&2; exit 2 ;;
esac
