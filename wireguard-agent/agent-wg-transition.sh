#!/usr/bin/env bash
set -Eeuo pipefail

readonly script_path="$(readlink -f -- "${BASH_SOURCE[0]}")"
readonly repo_dir="$(cd -- "$(dirname -- "$script_path")/.." && pwd)"
readonly network_env="${repo_dir}/wireguard-agent/network.env"
# shellcheck source=wireguard-agent/network.env
source "$network_env"
readonly user_name='julien'
readonly namespace='agent-wg'
readonly current_session='desktop-home-codex'
readonly agent_unit='agent-wg-sandbox.service'
readonly user_agent_unit='codex-remote-control-agent-wg.service'
readonly host_codex_unit='codex-remote-control.service'

namespace_started=0
cutover_started=0

usage() {
    cat <<'EOF'
Usage:
  agent-wg-transition.sh activate   Move the Codex daemon and desktop-home-codex to agent-wg.
  agent-wg-transition.sh recover    Restore desktop-home-codex and Codex daemon to the host.
  agent-wg-transition.sh status     Show the current service placement.

Run activate or recover from a separate interactive WSL terminal. Activation
restarts only desktop-home-codex; CCPocket Bridge, Caddy, and other sessions
stay on the host.
EOF
}

fail() {
    printf 'Error: %s\n' "$*" >&2
    return 1
}

require_user() {
    [[ "$(id -un)" == "$user_name" ]] || fail "Run this as ${user_name}, not root."
    [[ -t 0 ]] || fail 'Run this from an interactive WSL terminal so sudo can prompt and the script survives the session restart.'
    export XDG_RUNTIME_DIR="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}"
    export DBUS_SESSION_BUS_ADDRESS="${DBUS_SESSION_BUS_ADDRESS:-unix:path=${XDG_RUNTIME_DIR}/bus}"
    [[ -S "${XDG_RUNTIME_DIR}/bus" ]] || fail 'The julien systemd user bus is unavailable; use a logged-in WSL session.'
    if [[ -n "${TMUX:-}" ]]; then
        local session
        session="$(tmux display-message -p '#S' 2>/dev/null || true)"
    if [[ -n "$session" ]] && systemctl --user is-active --quiet "ai-session@${session}.service"; then
            fail 'Run this from a shell outside desktop-home-codex; activation restarts that session.'
        fi
    fi
}

set_current_namespace() {
    local target="$1"
    python3 - "${repo_dir}/ai-sessions/profiles/desktop/desktop-home-codex.env" \
        "${HOME}/.config/ai-sessions/desktop-home-codex.env" "$target" <<'PY'
from pathlib import Path
import sys

for name in sys.argv[1:3]:
    path = Path(name)
    lines = [line for line in path.read_text().splitlines()
             if not line.startswith("NETWORK_NAMESPACE=")]
    lines.append(f"NETWORK_NAMESPACE={sys.argv[3]}")
    path.write_text("\n".join(lines) + "\n")
PY
}

current_codex_pid_in_namespace() {
    local pids pid args
    pids="$(sudo ip netns pids "$namespace" 2>/dev/null || true)"
    while IFS= read -r pid; do
        [[ -n "$pid" ]] || continue
        args="$(ps -p "$pid" -o args= 2>/dev/null || true)"
        if [[ "$args" == *"resume "* && "$args" == *"-C /home/julien"* \
            && ( "$args" == *"@openai/codex"* || "$args" == *"/bin/codex "* ) ]]; then
            printf '%s\n' "$pid"
            return 0
        fi
    done <<<"$pids"
    return 1
}

codex_daemon_pid_in_namespace() {
    local pids pid args
    pids="$(sudo ip netns pids "$namespace" 2>/dev/null || true)"
    while IFS= read -r pid; do
        [[ -n "$pid" ]] || continue
        args="$(ps -p "$pid" -o args= 2>/dev/null || true)"
        if [[ "$args" == *"app-server --remote-control"* ]]; then
            printf '%s\n' "$pid"
            return 0
        fi
    done <<<"$pids"
    return 1
}

wait_for_codex_daemon() {
    local pid
    for ((attempt = 1; attempt <= 30; attempt++)); do
        pid="$(codex_daemon_pid_in_namespace || true)"
        if [[ -n "$pid" ]]; then
            printf 'Shared Codex app-server process %s is inside %s.\n' "$pid" "$namespace"
            return 0
        fi
        sleep 1
    done
    fail 'The shared Codex app-server process did not start inside agent-wg.'
}

wait_for_current_codex() {
    local pid
    for ((attempt = 1; attempt <= 90; attempt++)); do
        pid="$(current_codex_pid_in_namespace || true)"
        if [[ -n "$pid" ]]; then
            printf 'desktop-home-codex process %s is inside %s.\n' "$pid" "$namespace"
            return 0
        fi
        sleep 1
    done
    fail 'desktop-home-codex did not start inside agent-wg within 90 seconds.'
}

restore_unit_link() {
    local unit_path="$1" source_path="$2"
    ln -sfn "$source_path" "$unit_path"
}

disable_but_keep_unit_file() {
    local unit="$1" source="$2" target="${HOME}/.config/systemd/user/${1}"
    systemctl --user disable "$unit" >/dev/null 2>&1 || true
    restore_unit_link "$target" "$source"
}

enable_root_namespace() {
    sudo systemctl enable agent-wg-sandbox.service
}

terminate_namespace_processes() {
    local pids
    pids="$(sudo ip netns pids "$namespace" 2>/dev/null || true)"
    if [[ -n "$pids" ]]; then
        printf 'Stopping leftover processes in %s: %s\n' "$namespace" "${pids//$'\n'/ }"
        sudo /usr/bin/kill -TERM $pids 2>/dev/null || true
        sleep 3
        pids="$(sudo ip netns pids "$namespace" 2>/dev/null || true)"
        if [[ -n "$pids" ]]; then
            printf 'Force-stopping remaining namespace processes: %s\n' "${pids//$'\n'/ }"
            sudo /usr/bin/kill -KILL $pids 2>/dev/null || true
        fi
    fi
}

recover_worker() {
    printf '%s\n' 'Returning desktop-home-codex and the Codex daemon to the host...'
    systemctl --user stop "ai-session@${current_session}.service" \
        "$user_agent_unit" "$host_codex_unit" 2>/dev/null || true

    terminate_namespace_processes
    sudo systemctl disable --now "$agent_unit" >/dev/null 2>&1 || true
    if sudo ip netns list | awk '{print $1}' | grep -Fxq "$namespace"; then
        sudo /usr/local/libexec/agent-wg-netns down
    fi

    set_current_namespace host

    disable_but_keep_unit_file "$user_agent_unit" \
        "${repo_dir}/wireguard-agent/codex-remote-control-agent-wg.service"
    disable_but_keep_unit_file "$host_codex_unit" \
        "${repo_dir}/ai-sessions/codex-remote-control.service"
    systemctl --user daemon-reload

    printf '%s\n' 'Restarting the current session on the host...'
    local host_codex_restored=1
    if ! systemctl --user enable --now "$host_codex_unit"; then
        host_codex_restored=0
        printf '%s\n' 'Warning: the host Codex daemon could not reconnect; CCPocket Bridge and Caddy were left untouched.' >&2
    fi
    systemctl --user restart "ai-session@${current_session}.service"
    printf '\nCurrent Codex session is back on the host. CCPocket Bridge and Caddy remain running as before.\n'
    if [[ "$host_codex_restored" == 0 ]]; then
        printf '%s\n' 'Host Codex Remote Control remains unavailable; restore host outbound DNS/network or continue with the CLI session.' >&2
    fi
}

handle_activation_error() {
    local status="$1" line="$2" command="$3"
    trap - ERR
    printf '\nActivation failed at line %s: %s\n' "$line" "$command" >&2
    if [[ "$cutover_started" == 1 ]]; then
        printf '%s\n' 'Automatically restoring host services now.'
        "$0" --worker-recover || printf 'Automatic recovery failed. Run: %s recover\n' "$0" >&2
    elif [[ "$namespace_started" == 1 ]]; then
        printf '%s\n' 'Stopping the test namespace; existing host services remain in place.'
        sudo systemctl stop "$agent_unit" || true
    fi
    exit "$status"
}

activate_worker() {
    trap 'handle_activation_error "$?" "$LINENO" "$BASH_COMMAND"' ERR
    require_user
    sudo -v
    [[ -r "${HOME}/.config/wireguard/freebox-agent.conf" ]] || fail 'The private Freebox profile is missing.'
    cmp -s "$network_env" /etc/agent-wg/network.env || fail 'The installed network.env differs; rerun install-agent-wg.sh.'
    ip -4 route show default dev eth3 | grep -q . || fail 'The normal WSL LAN route on eth3 is missing.'

    printf '%s\n' 'This moves only the shared Codex daemon and desktop-home-codex.'
    printf '%s\n' 'CCPocket Bridge, Caddy, and all other sessions remain on the host.'
    read -r -p 'Confirm NordVPN is off and continue from this separate WSL terminal? [y/N] ' answer
    [[ "$answer" =~ ^[Yy]$ ]] || fail 'Activation cancelled; no services were changed.'

    cutover_started=1
    printf '%s\n' 'Starting the WireGuard namespace and testing its egress...'
    sudo systemctl start "$agent_unit"
    namespace_started=1
    local egress_ip handshake
    egress_ip="$("${HOME}/.local/bin/agent-wg-run" -- /usr/bin/curl -4 -fsS --max-time 20 https://api.ipify.org)"
    [[ "$egress_ip" =~ ^[0-9]{1,3}(\.[0-9]{1,3}){3}$ ]] || fail 'The namespace did not return a valid IPv4 egress address.'
    handshake="$(sudo ip netns exec "$namespace" wg show wg-agent latest-handshakes | awk 'NR == 1 {print $2}')"
    [[ "${handshake:-0}" =~ ^[1-9][0-9]*$ ]] || fail 'WireGuard did not complete a handshake.'
    printf 'WireGuard handshake succeeded; sandbox egress IPv4: %s\n' "$egress_ip"

    set_current_namespace agent-wg
    printf '%s\n' 'Moving the shared Codex daemon into agent-wg...'
    systemctl --user stop "$host_codex_unit" 2>/dev/null || true
    disable_but_keep_unit_file "$host_codex_unit" \
        "${repo_dir}/ai-sessions/codex-remote-control.service"
    systemctl --user daemon-reload

    local daemon_started=1 daemon_pid
    if ! systemctl --user enable --now "$user_agent_unit"; then
        daemon_started=0
        printf '%s\n' 'Codex Remote Control registration did not finish; checking whether its app-server daemon is running in the namespace.' >&2
    fi
    daemon_pid="$(wait_for_codex_daemon)"
    printf 'Shared Codex app-server process %s is inside %s.\n' "$daemon_pid" "$namespace"

    enable_root_namespace
    systemctl --user restart "ai-session@${current_session}.service"
    wait_for_current_codex
    systemctl --user is-active "ai-session@${current_session}.service" >/dev/null
    sudo systemctl is-active "$agent_unit" >/dev/null
    namespace_started=0
    cutover_started=0
    trap - ERR
    printf '\nMigration is active. The current Codex transcript has been restarted in agent-wg.\n'
    printf '%s\n' 'CCPocket Bridge, Caddy, and other sessions remain on the host.'
    if [[ "$daemon_started" == 0 ]]; then
        printf '%s\n' 'The current CLI session is sandboxed; shared Codex Remote Control can be repaired later.' >&2
    fi
}

status() {
    printf '%s\n' '--- network namespace ---'
    sudo systemctl is-active "$agent_unit" 2>/dev/null || true
    sudo ip netns list
    printf '%s\n' '--- Codex services ---'
    systemctl --user is-active "$user_agent_unit" "$host_codex_unit" 2>/dev/null || true
    printf '%s\n' '--- CCPocket Bridge ---'
    systemctl --user is-active ccpocket-bridge-host.service ccpocket-bridge.service 2>/dev/null || true
    printf '%s\n' '--- current session ---'
    systemctl --user is-active "ai-session@${current_session}.service" 2>/dev/null || true
}

case "${1:-}" in
    activate) activate_worker ;;
    recover) require_user; sudo -v; recover_worker ;;
    status) status ;;
    --worker-recover) recover_worker ;;
    *) usage; exit 2 ;;
esac
