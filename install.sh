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
#  Usage: ./install.sh
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
    "tmux/tmux.conf|${HOME}/.tmux.conf"
    "claude/settings.json|${HOME}/.claude/settings.json"
    "claude/CLAUDE.md|${HOME}/.claude/CLAUDE.md"
    "claude/RTK.md|${HOME}/.claude/RTK.md"
    "claude/rules/common.md|${HOME}/.claude/rules/common.md"
    "claude/rules/python.md|${HOME}/.claude/rules/python.md"
    "claude/statusline/statusline.sh|${HOME}/.claude/claude-cli-status/statusline.sh"
    "ai-sessions/ai-session@.service|${HOME}/.config/systemd/user/ai-session@.service"
    "ai-sessions/ai-session-watch|${HOME}/.local/bin/ai-session-watch"
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

echo -e "${BLUE}Linking config from ${REPO_DIR}...${NC}"
for pair in "${LINKS[@]}"; do
    link_one "${pair%%|*}" "${pair##*|}"
done

chmod +x "${REPO_DIR}/claude/statusline/statusline.sh" "${REPO_DIR}/ai-sessions/ai-session-watch"

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
