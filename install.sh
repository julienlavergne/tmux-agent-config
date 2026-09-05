#!/usr/bin/env bash
# ═══════════════════════════════════════════════════════════════════════════════
#  tmux-agent-config installer
# ═══════════════════════════════════════════════════════════════════════════════
#
#  Symlinks the generic tmux / Claude Code / AI-session-service config in this
#  repo into place. Any existing real file at a target path is backed up
#  (suffixed .bak-<timestamp>) before being replaced with a symlink, so this
#  is safe to re-run.
#
#  Usage:
#    ./install.sh                 Link config into place (default)
#    ./install.sh --clean-backups Remove .bak-<timestamp> files left by past
#                                  installs, once you've verified the symlinked
#                                  config works. Prompts for confirmation.
#
# ═══════════════════════════════════════════════════════════════════════════════

set -e

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TIMESTAMP="$(date +%Y%m%d%H%M%S)"

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# "repo-relative-path|target-path" pairs
LINKS=(
    "bash/inputrc|${HOME}/.inputrc"
    "tmux/tmux.conf|${HOME}/.tmux.conf"
    "tmux/tmux-picker|${HOME}/.local/bin/tmux-picker"
    "claude/settings.json|${HOME}/.claude/settings.json"
    "claude/CLAUDE.md|${HOME}/.claude/CLAUDE.md"
    "claude/rules/common.md|${HOME}/.claude/rules/common.md"
    "claude/rules/python.md|${HOME}/.claude/rules/python.md"
    "claude/statusline/statusline.sh|${HOME}/.claude/claude-cli-status/statusline.sh"
    "ai-sessions/ai-session@.service|${HOME}/.config/systemd/user/ai-session@.service"
    "ai-sessions/ai-session-watch|${HOME}/.local/bin/ai-session-watch"
    "ai-sessions/restart-ai-sessions|${HOME}/.local/bin/restart-ai-sessions"
)

link_one() {
    local src="${REPO_DIR}/$1"
    local dst="$2"

    if [[ ! -e "$src" ]]; then
        echo -e "  ${YELLOW}skip${NC} $dst (source $src missing)"
        return
    fi

    mkdir -p "$(dirname "$dst")"

    if [[ -L "$dst" ]]; then
        if [[ "$(readlink -f "$dst")" == "$(readlink -f "$src")" ]]; then
            echo -e "  ${GREEN}ok${NC}   $dst (already linked)"
            return
        fi
        rm "$dst"
    elif [[ -e "$dst" ]]; then
        mv "$dst" "${dst}.bak-${TIMESTAMP}"
        echo -e "  ${YELLOW}backed up${NC} $dst -> ${dst}.bak-${TIMESTAMP}"
    fi

    ln -s "$src" "$dst"
    echo -e "  ${GREEN}linked${NC} $dst -> $src"
}

do_install() {
    echo -e "${BLUE}Linking config from ${REPO_DIR}...${NC}"
    for pair in "${LINKS[@]}"; do
        link_one "${pair%%|*}" "${pair##*|}"
    done

    chmod +x "${REPO_DIR}/tmux/tmux-picker" "${REPO_DIR}/claude/statusline/statusline.sh" "${REPO_DIR}/ai-sessions/ai-session-watch" "${REPO_DIR}/ai-sessions/restart-ai-sessions"

    if command -v systemctl >/dev/null 2>&1; then
        systemctl --user daemon-reload
        echo -e "${GREEN}✓ systemd user daemon reloaded${NC}"
    fi

    echo ""
    echo -e "${BLUE}Done.${NC} Per-machine steps still needed:"
    echo "  1. For each tmux/agent session you want running here, create an env file:"
    echo "       cp ${REPO_DIR}/ai-sessions/env.example ~/.config/ai-sessions/<device>-<foldername>-<agent>.env"
    echo "     then edit CWD/AGENT in it."
    echo "  2. Enable it:"
    echo "       systemctl --user enable --now ai-session@<device>-<foldername>-<agent>.service"
}

do_clean_backups() {
    local targets=()
    for pair in "${LINKS[@]}"; do
        local dst="${pair##*|}"
        while IFS= read -r -d '' f; do
            targets+=("$f")
        done < <(find "$(dirname "$dst")" -maxdepth 1 -name "$(basename "$dst").bak-*" -print0 2>/dev/null)
    done

    if [[ "${#targets[@]}" -eq 0 ]]; then
        echo -e "${GREEN}No backup files found.${NC}"
        return
    fi

    echo -e "${YELLOW}The following backup files will be deleted:${NC}"
    printf '  %s\n' "${targets[@]}"
    read -r -p "Proceed? [y/N] " reply
    if [[ "$reply" =~ ^[Yy]$ ]]; then
        rm -f "${targets[@]}"
        echo -e "${GREEN}✓ Removed ${#targets[@]} backup file(s).${NC}"
    else
        echo "Aborted."
    fi
}

case "${1:-}" in
    --clean-backups) do_clean_backups ;;
    "")              do_install ;;
    *)
        echo "Usage: $0 [--clean-backups]"
        exit 1
        ;;
esac
