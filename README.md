# tmux-agent-config

Generic tmux + Codex / Claude Code + background AI-session-service config, meant to be
symlinked into place rather than copied — edit the file in the repo, the
live config updates immediately (and is already tracked by git).

## What's here

| Path | Symlinked to | Purpose |
|---|---|---|
| `bash/inputrc` | `~/.inputrc` | Readline/autocomplete behavior: menu-complete tab cycling, case-insensitive and colored completion, history search with arrow keys. |
| `tmux/tmux.conf` | `~/.tmux.conf` | Mouse support, clipboard integration, vi copy-mode, scrollback, window titles. |
| `tmux/tmux-picker` | `~/.local/bin/tmux-picker` | Login-shell picker: attach/create/delete tmux sessions interactively on login. Uses `fzf` for fuzzy search when it's installed, falls back to a plain numbered menu (no dependencies beyond bash + tmux) when it isn't. |
| `claude/settings.json` | `~/.claude/settings.json` | Claude Code permission allowlist, statusline wiring, theme/notification prefs. |
| `shared/AGENTS.md` | `~/.codex/AGENTS.md`, `~/.claude/rules/preferences.md` | Shared personal instructions: candid mentoring, environment, tooling, concise answers, questions, content style, and feature quality. |
| `claude/CLAUDE.md` | `~/.claude/CLAUDE.md` | Claude-specific instructions: tmux sessions, worktree isolation, multi-agent feature workflow, and codebase navigation. |
| `claude/rules/common.md` | `~/.claude/rules/common.md` | Engineering rules (code quality, security, testing, git, review) auto-loaded by Claude Code. |
| `claude/rules/python.md` | `~/.claude/rules/python.md` | Python-specific conventions, auto-loaded by Claude Code. |
| `claude/statusline/statusline.sh` | `~/.claude/claude-cli-status/statusline.sh` | Custom statusline: project/branch, model, context usage bar, token counts, cost, rate limits. |
| `ai-sessions/ai-session@.service` | `~/.config/systemd/user/ai-session@.service` | systemd user template unit that keeps a named tmux session alive running `claude` or `copilot`. |
| `ai-sessions/ai-session-watch` | `~/.local/bin/ai-session-watch` | Watcher script the unit runs: creates the tmux session if missing, resumes the most recent matching transcript, respawns on crash. |
| `ai-sessions/env.example` | *(not symlinked — a template)* | Per-session `CWD`/`AGENT` env file format consumed by the systemd unit. |

## Install (this machine or a new one)

Edit `shared/AGENTS.md` for preferences that apply to both Codex and Claude Code. Both global paths link to that file; keep Claude-specific tools and workflows in `claude/CLAUDE.md`. Claude's engineering and language rules remain in `claude/rules/`. Start a new agent session after changing instructions so it loads the current content.

```bash
git clone git@github.com:julienlavergne/tmux-agent-config.git ~/workspace/tmux-agent-config
~/workspace/tmux-agent-config/install.sh
```

Then add the login picker hook to `~/.profile` (once per machine, before the PATH block):

```bash
# Tmux session picker (runs on interactive login, skipped when already in tmux)
if [[ -z "$TMUX" && -t 0 ]] && command -v tmux &>/dev/null; then
    _tp_tmp=$(mktemp)
    bash ~/.local/bin/tmux-picker "$_tp_tmp"
    _tp_choice=$(cat "$_tp_tmp" 2>/dev/null); rm -f "$_tp_tmp"
    case "$_tp_choice" in
        tmux:*) exec tmux attach-session -t "${_tp_choice#tmux:}" ;;
        new:*)  exec tmux new-session -A -s "${_tp_choice#new:}" ;;
    esac
    unset _tp_tmp _tp_choice
fi
```

`fzf` is optional (`apt install fzf` or `brew install fzf` for the fuzzy-search
UI) — `tmux-picker` falls back to a plain numbered menu with the same
attach/create/delete behavior when it isn't installed.

`install.sh` symlinks every path above into place. If a real file already
exists at a target, it's backed up to `<path>.bak-<timestamp>` first — safe
to re-run any time. It also runs `systemctl --user daemon-reload` if
`systemctl` is available.

Once you've confirmed the symlinked config works, remove the backups:

```bash
~/workspace/tmux-agent-config/install.sh --clean-backups
```

This finds every `<path>.bak-*` left by past installs and deletes them after
a confirmation prompt — no need to hunt them down by hand on each machine.

## Per-machine session setup

The systemd unit and watcher script are generic, but *which* sessions run is
per-machine (different projects live on different boxes). For each session:

```bash
cp ai-sessions/env.example ~/.config/ai-sessions/<device>-<foldername>-<agent>.env
# edit CWD and AGENT in it
systemctl --user enable --now ai-session@<device>-<foldername>-<agent>.service
```

Session names follow `<device>-<foldername>-<agent>` (see `CLAUDE.md`):
`device` is `desktop` or `laptop`, `foldername` is the working directory's
basename, `agent` is `claude` or `copilot`. This keeps the tmux session name,
the systemd instance name, and the Claude Code `--rc` remote-control title in
sync so sessions are recognizable from FleetView / Remote Control on Android.

## What's deliberately *not* here

- `~/.config/ai-sessions/*.env` — per-machine, points at local project paths.
- `~/.claude.json`, `~/.claude/.credentials.json` — session/auth state, not config.
- Anything under `~/.claude/projects/` (including the memory system) — conversation history and learned memory, not portable setup.
