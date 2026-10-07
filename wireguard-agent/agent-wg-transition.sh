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
readonly bridge_env="${HOME}/.config/ccpocket/bridge.env"
readonly agent_unit='agent-wg-sandbox.service'
readonly user_agent_unit='codex-remote-control-agent-wg.service'
readonly bridge_agent_unit='ccpocket-bridge.service'
readonly bridge_host_unit='ccpocket-bridge-host.service'
readonly host_codex_unit='codex-remote-control.service'
readonly caddy_project='reverse-proxy'
readonly caddy_agent_compose="${repo_dir}/reverse-proxy/compose.yaml"
readonly caddy_host_compose="${repo_dir}/reverse-proxy/compose.host.yaml"

namespace_started=0
cutover_started=0

usage() {
    cat <<'EOF'
Usage:
  agent-wg-transition.sh activate   Finish the move to agent-wg.
  agent-wg-transition.sh recover    Restore the host-network fallback.
  agent-wg-transition.sh status     Show the current service placement.

Run activate or recover from a separate interactive WSL terminal. Activation
restarts desktop-home-codex last; that terminal remains available while this
conversation reconnects.
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
            fail 'Run this from a shell outside an AI session; activation restarts the current session last.'
        fi
    fi
}

ai_units() {
    local -A seen=()
    local unit name
    while IFS= read -r unit; do
        [[ -n "$unit" ]] && seen["$unit"]=1
    done < <(
        systemctl --user list-units --all --type=service --no-legend --no-pager \
            | awk '{for(i=1;i<=NF;i++) if($i ~ /^ai-session@.*\.service$/) print $i}'
    )
    while IFS= read -r name; do
        [[ -n "$name" ]] && seen["ai-session@${name}.service"]=1
    done <"${repo_dir}/ai-sessions/profiles/desktop/enabled-sessions.txt"
    printf '%s\n' "${!seen[@]}" | sort
}

stop_ai_sessions() {
    mapfile -t units < <(ai_units)
    if ((${#units[@]})); then
        systemctl --user stop "${units[@]}" || true
    fi
}

restart_ai_sessions() {
    local include_current="${1:-yes}"
    local unit
    local -a all=() first=()
    mapfile -t all < <(ai_units)
    for unit in "${all[@]}"; do
        if [[ "$include_current" == no && "$unit" == "ai-session@${current_session}.service" ]]; then
            continue
        fi
        first+=("$unit")
    done
    if [[ "$include_current" == yes ]]; then
        for unit in "${first[@]}"; do
            [[ "$unit" == "ai-session@${current_session}.service" ]] && continue
            systemctl --user restart "$unit"
        done
        systemctl --user restart "ai-session@${current_session}.service"
    elif ((${#first[@]})); then
        systemctl --user restart "${first[@]}"
    fi
}

set_session_namespace() {
    local target="$1"
    python3 - "${repo_dir}/ai-sessions/profiles/desktop" "${HOME}/.config/ai-sessions" "$target" <<'PY'
from pathlib import Path
import sys

target = sys.argv[3]
for directory in (Path(sys.argv[1]), Path(sys.argv[2])):
    if not directory.is_dir():
        continue
    for path in directory.glob("*.env"):
        lines = [line for line in path.read_text().splitlines()
                 if not line.startswith("NETWORK_NAMESPACE=")]
        lines.append(f"NETWORK_NAMESPACE={target}")
        path.write_text("\n".join(lines) + "\n")
PY
}

set_bridge_mode() {
    local mode="$1" mdns="$2"
    python3 - "$bridge_env" "$mode" "$mdns" <<'PY'
from pathlib import Path
import sys

path = Path(sys.argv[1])
mode, mdns = sys.argv[2:]
lines = [line for line in path.read_text().splitlines()
         if not line.startswith(("BRIDGE_HOST=", "BRIDGE_DISABLE_MDNS="))]
if mode == "host":
    lines.append("BRIDGE_HOST=0.0.0.0")
lines.append(f"BRIDGE_DISABLE_MDNS={mdns}")
path.write_text("\n".join(lines) + "\n")
path.chmod(0o600)
PY
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
    printf '%s\n' 'Stopping sandboxed sessions and services...'
    stop_ai_sessions
    systemctl --user stop "$bridge_agent_unit" "$bridge_host_unit" \
        "$user_agent_unit" "$host_codex_unit" 2>/dev/null || true
    docker stop caddy >/dev/null 2>&1 || true

    terminate_namespace_processes
    sudo systemctl disable --now "$agent_unit" >/dev/null 2>&1 || true
    if sudo ip netns list | awk '{print $1}' | grep -Fxq "$namespace"; then
        sudo /usr/local/libexec/agent-wg-netns down
    fi

    set_session_namespace host
    set_bridge_mode host 0

    disable_but_keep_unit_file "$user_agent_unit" \
        "${repo_dir}/wireguard-agent/codex-remote-control-agent-wg.service"
    disable_but_keep_unit_file "$host_codex_unit" \
        "${repo_dir}/ai-sessions/codex-remote-control.service"
    systemctl --user daemon-reload

    printf '%s\n' 'Restoring host-network Codex and CCPocket services...'
    systemctl --user enable --now "$host_codex_unit"
    systemctl --user enable --now "$bridge_host_unit"
    docker compose -p "$caddy_project" -f "$caddy_host_compose" up -d caddy \
        || printf '%s\n' 'Caddy could not be restored; use direct Meshnet access to the host Bridge on port 8765.' >&2

    systemctl --user daemon-reload
    restart_ai_sessions yes
    printf '\nHost fallback restored. Connect CCPocket to wss://julienlavergne.asuscomm.com:8765 or, on Meshnet, ws://julien-desktop-meshnet:8765.\n'
}

handle_activation_error() {
    local status="$1"
    trap - ERR
    printf '\nActivation failed. '
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
    trap 'handle_activation_error "$?"' ERR
    require_user
    sudo -v
    [[ -r "$bridge_env" ]] || fail "Missing CCPocket settings: ${bridge_env}"
    [[ -r "${HOME}/.config/wireguard/freebox-agent.conf" ]] || fail 'The private Freebox profile is missing.'
    cmp -s "$network_env" /etc/agent-wg/network.env || fail 'The installed network.env differs; rerun install-agent-wg.sh.'
    ip -4 route show default dev eth3 | grep -q . || fail 'The normal WSL LAN route on eth3 is missing.'
    docker compose --env-file "$network_env" -p "$caddy_project" -f "$caddy_agent_compose" config -q
    docker exec -e "BRIDGE_HOST=${BRIDGE_HOST}" -e "BRIDGE_PORT=${BRIDGE_PORT}" \
        caddy caddy validate --config /etc/caddy/Caddyfile --adapter caddyfile >/dev/null

    printf '%s\n' 'The current CCPocket connection will pause while the Bridge moves.'
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

    set_session_namespace agent-wg
    set_bridge_mode agent-wg 1

    printf '%s\n' 'Moving CCPocket and Codex Remote Control into agent-wg...'
    systemctl --user stop "$bridge_agent_unit" "$bridge_host_unit" 2>/dev/null || true
    disable_but_keep_unit_file "$host_codex_unit" \
        "${repo_dir}/ai-sessions/codex-remote-control.service"
    disable_but_keep_unit_file "$bridge_host_unit" \
        "${repo_dir}/ccpocket/ccpocket-bridge-host.service"
    systemctl --user daemon-reload

    docker compose --env-file "$network_env" -p "$caddy_project" -f "$caddy_agent_compose" up -d caddy
    systemctl --user enable --now "$user_agent_unit"
    systemctl --user enable --now "$bridge_agent_unit"

    local namespace_ref bridge_pid codex_pid bridge_http public_http
    namespace_ref="$(sudo readlink "/run/netns/${namespace}")"
    bridge_pid="$(ps -eo pid=,uid=,comm=,args= | awk -v uid="$(id -u)" \
        '$2 == uid && $3 == "MainThread" && /@ccpocket\/bridge\/dist\/cli.js/ {print $1; exit}')"
    codex_pid="$(ps -eo pid=,uid=,comm=,args= | awk -v uid="$(id -u)" \
        '$2 == uid && $3 == "codex" && /app-server --remote-control/ {print $1; exit}')"
    [[ -n "$bridge_pid" && "$(readlink "/proc/${bridge_pid}/ns/net")" == "$namespace_ref" ]] || fail 'The CCPocket Bridge did not start inside agent-wg.'
    [[ -n "$codex_pid" && "$(readlink "/proc/${codex_pid}/ns/net")" == "$namespace_ref" ]] || fail 'The shared Codex daemon did not start inside agent-wg.'
    bridge_http="$(curl -4 -sS -o /dev/null -w '%{http_code}' --max-time 8 "http://${BRIDGE_HOST}:${BRIDGE_PORT}/")"
    [[ "$bridge_http" =~ ^[1-4][0-9][0-9]$ ]] || fail "The Bridge veth endpoint returned HTTP ${bridge_http}."
    docker exec caddy curl -4 -sS -o /dev/null -w '%{http_code}' --max-time 8 "http://${BRIDGE_HOST}:${BRIDGE_PORT}/" \
        | grep -Eq '^[1-4][0-9][0-9]$' || fail 'Caddy cannot reach the Bridge across the private veth.'
    public_http="$(curl -k -4 -sS -o /dev/null -w '%{http_code}' --max-time 12 \
        --connect-to julienlavergne.asuscomm.com:8765:127.0.0.1:18765 \
        https://julienlavergne.asuscomm.com:8765/)"
    [[ "$public_http" =~ ^[1-4][0-9][0-9]$ ]] || fail "The local TLS proxy returned HTTP ${public_http}."

    enable_root_namespace
    systemctl --user enable "$user_agent_unit"
    restart_ai_sessions no
    sleep 3
    systemctl --user restart "ai-session@${current_session}.service"
    sleep 3
    systemctl --user is-active "$agent_unit" "$user_agent_unit" "$bridge_agent_unit" \
        "ai-session@${current_session}.service" >/dev/null
    namespace_started=0
    cutover_started=0
    trap - ERR
    printf '\nMigration is active. The current Codex transcript has been restarted in agent-wg.\n'
    printf 'CCPocket public WSS: wss://julienlavergne.asuscomm.com:8765 (HTTP probe %s).\n' "$public_http"
}

status() {
    printf '%s\n' '--- network namespace ---'
    sudo systemctl is-active "$agent_unit" 2>/dev/null || true
    sudo ip netns list
    printf '%s\n' '--- CCPocket and Codex services ---'
    systemctl --user is-active "$bridge_agent_unit" "$bridge_host_unit" \
        "$user_agent_unit" "$host_codex_unit" 2>/dev/null || true
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
