#!/usr/bin/env bash
# Update agent CLIs and the installed CC Pocket Bridge without restarting sessions.
set -eo pipefail

update_daemon=false
for argument in "$@"; do
    case "$argument" in
        --update-daemon) update_daemon=true ;;
        --help|-h)
            echo "Usage: update-ai-clis [--update-daemon]"
            echo "Updates Claude, stable Copilot, Codex, and CC Pocket Bridge when installed."
            echo "--update-daemon also replaces the Codex daemon package and may interrupt work."
            exit 0
            ;;
        *) echo "Unknown option: $argument" >&2; exit 2 ;;
    esac
done

state_dir="${AI_CLIS_STATE_DIR:-${HOME}/.local/state/ai-cli-updates}"
mkdir -p "$state_dir"
exec 9>"${state_dir}/update.lock"
if ! flock -n 9; then
    echo "An agent CLI update is already running; skipping this invocation."
    exit 0
fi

# Load nvm before enabling nounset; nvm's startup script uses optional variables.
export NVM_DIR="${NVM_DIR:-${HOME}/.nvm}"
if [[ -s "${NVM_DIR}/nvm.sh" ]]; then
    if ! . "${NVM_DIR}/nvm.sh"; then
        echo "[WARN] Could not load nvm; trying the existing Node/npm PATH." >&2
    fi
fi
set -u
bin_dir="${AI_CLIS_BIN_DIR:-${HOME}/.local/bin}"
export PATH="${bin_dir}:${PATH}"
failures=()

version_of() {
    "$1" --version 2>/dev/null | sed -n '1p' || printf 'unknown\n'
}

run_update() {
    local label="$1" binary="$2" before after result
    shift 2
    before="$(version_of "$binary")"
    printf '\n[INFO] Updating %s (%s)...\n' "$label" "$before"
    if "$@" </dev/null; then
        after="$(version_of "$binary")"
        if [[ -z "$after" || "$after" == unknown ]]; then
            printf '[ERROR] %s update returned success, but the installed CLI could not report its version.\n' "$label" >&2
            failures+=("$label")
            return
        fi
        if [[ "$before" == "$after" ]]; then
            printf '[OK] %s: %s\n' "$label" "$after"
        else
            printf '[OK] %s: %s -> %s\n' "$label" "$before" "$after"
        fi
    else
        result=$?
        printf '[ERROR] %s update failed (exit %s); continuing with the other tools.\n' "$label" "$result" >&2
        failures+=("$label")
    fi
}

update_codex() {
    local latest installed
    latest="$(npm view @openai/codex@latest version)" || return
    installed="$("${bin_dir}/codex" --version)" || return
    if [[ "$installed" == "codex-cli $latest" ]]; then
        printf 'Codex already matches the latest release (%s).\n' "$latest"
        return 0
    fi
    npm install -g @openai/codex@latest
}

run_update "Claude" "${bin_dir}/claude" "${bin_dir}/claude" update
run_update "Copilot" "${bin_dir}/copilot" "${bin_dir}/copilot" update stable
run_update "Codex" "${bin_dir}/codex" update_codex

if npm list -g @ccpocket/bridge --depth=0 >/dev/null 2>&1; then
    run_update "CC Pocket Bridge" ccpocket-bridge npm update -g @ccpocket/bridge
fi

if [[ "$update_daemon" == true ]]; then
    run_update "Codex daemon package" "${bin_dir}/codex" "${bin_dir}/codex" app-server daemon update --from-cli --yes
else
    echo "[INFO] Running agents and the Codex daemon are not restarted. Use --update-daemon when ready to replace the daemon package."
fi

if ((${#failures[@]})); then
    printf '\n[ERROR] Updates failed for: %s\n' "${failures[*]}" >&2
    exit 1
fi
printf '\n[OK] All requested package updates completed.\n'
