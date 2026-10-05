#!/usr/bin/env bash
# update-ai-clis.sh — update Claude, Copilot, and Codex CLIs

set -euo pipefail

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

ok()   { echo -e "${GREEN}✓${NC} $*"; }
info() { echo -e "${YELLOW}→${NC} $*"; }
fail() { echo -e "${RED}✗${NC} $*"; }

# ── Claude ────────────────────────────────────────────────────────────────────
echo
info "Updating Claude CLI..."
CLAUDE_BEFORE=$(~/.local/bin/claude --version 2>/dev/null | head -1 || echo "unknown")
if ~/.local/bin/claude update 2>&1 | grep -qi "already up.to.date\|no update\|latest"; then
    ok "Claude: already up to date ($CLAUDE_BEFORE)"
else
    CLAUDE_AFTER=$(~/.local/bin/claude --version 2>/dev/null | head -1 || echo "unknown")
    ok "Claude: $CLAUDE_BEFORE → $CLAUDE_AFTER"
fi

# ── Copilot ───────────────────────────────────────────────────────────────────
echo
info "Updating Copilot CLI..."
COPILOT_BEFORE=$(~/.local/bin/copilot --version 2>/dev/null | head -1 || echo "unknown")
if ~/.local/bin/copilot /update 2>&1 | grep -qi "already up.to.date\|no update\|latest"; then
    ok "Copilot: already up to date ($COPILOT_BEFORE)"
else
    COPILOT_AFTER=$(~/.local/bin/copilot --version 2>/dev/null | head -1 || echo "unknown")
    ok "Copilot: $COPILOT_BEFORE → $COPILOT_AFTER"
fi

# ── Codex ─────────────────────────────────────────────────────────────────────
echo
info "Updating Codex CLI..."
export NVM_DIR="${HOME}/.nvm"
[ -s "${NVM_DIR}/nvm.sh" ] && . "${NVM_DIR}/nvm.sh"

CODEX_BEFORE=$(~/.local/bin/codex --version 2>/dev/null || echo "unknown")
npm update -g @openai/codex 2>&1 | tail -3
CODEX_AFTER=$(~/.local/bin/codex --version 2>/dev/null || echo "unknown")
if [[ "$CODEX_BEFORE" == "$CODEX_AFTER" ]]; then
    ok "Codex: already up to date ($CODEX_BEFORE)"
else
    ok "Codex: $CODEX_BEFORE → $CODEX_AFTER"
fi

# ── Codex daemon update ───────────────────────────────────────────────────────
echo
info "Updating Codex app-server daemon..."
if ~/.local/bin/codex app-server daemon update 2>&1 | grep -qi "already\|up.to.date\|no update"; then
    ok "Codex daemon: already up to date"
else
    ok "Codex daemon: updated"
fi

echo
ok "All done."
