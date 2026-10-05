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
| `claude/settings.local.json` | `~/.claude/settings.local.json` | Additional local filesystem read permissions. |
| `codex/config.toml` | `~/.codex/config.toml` *(copied only when absent)* | Codex model, reasoning, sandbox, service tier, terminal status-line and plugin preferences. |
| `codex/profiles/desktop.toml` | *(snapshot, not linked)* | Full desktop Codex configuration, including project trust, local marketplace paths and approved hook hashes. |
| `codex/launcher` | `~/.local/bin/codex` | Launches Codex from the active nvm Node installation without pinning a Node version path. |
| `shared/AGENTS.md` | `~/.codex/AGENTS.md`, `~/.claude/rules/preferences.md` | Shared personal instructions: candid mentoring, environment, tooling, concise answers, questions, content style, and feature quality. |
| `claude/CLAUDE.md` | `~/.claude/CLAUDE.md` | Claude-specific instructions: tmux sessions, worktree isolation, multi-agent feature workflow, and codebase navigation. |
| `claude/rules/common.md` | `~/.claude/rules/common.md` | Engineering rules (code quality, security, testing, git, review) auto-loaded by Claude Code. |
| `claude/rules/python.md` | `~/.claude/rules/python.md` | Python-specific conventions, auto-loaded by Claude Code. |
| `claude/rules/cpp.md`, `dart.md`, `rust.md` | `~/.claude/rules/<language>.md` | C++, Dart/Flutter and Rust instructions, loaded for matching files. |
| `claude/statusline/statusline.sh` | `~/.claude/claude-cli-status/statusline.sh` | Custom statusline: project/branch, model, context usage bar, token counts, cost, rate limits. |
| `ai-sessions/ai-session@.service` | `~/.config/systemd/user/ai-session@.service` | systemd user template unit that keeps a named tmux session alive running `claude`, `copilot`, or `codex`. |
| `ai-sessions/ai-session-watch` | `~/.local/bin/ai-session-watch` | Watcher script the unit runs: creates the tmux session if missing, resumes the most recent matching transcript, respawns on crash. |
| `ai-sessions/ai-session-codex`, `ai-session-copilot` | *(loaded beside the watcher)* | Python helpers that preserve each service's foreground conversation identity. |
| `ai-sessions/codex-remote-control.service` | `~/.config/systemd/user/codex-remote-control.service` | Starts the Codex remote-control daemon. |
| `ai-sessions/profiles/desktop/*.env` | `~/.config/ai-sessions/*.env` *(with `--sessions desktop`)* | Desktop session definitions; installation does not start or restart sessions. |
| `ai-sessions/profiles/desktop/enabled-sessions.txt` | *(restoration inventory)* | Names of enabled desktop AI-session services. |
| `ai-sessions/restart-ai-sessions` | `~/.local/bin/restart-ai-sessions` | Restarts `ai-session@` systemd units on this host — all of them, or specific names passed as arguments. |
| `ai-sessions/update-ai-clis.sh` | `~/.local/bin/update-ai-clis`, `~/update-ai-clis.sh` | Updates Claude, Copilot, Codex, the Codex app-server daemon, and CC Pocket Bridge when installed. The home-directory link preserves the original invocation. |
| `ccpocket/ccpocket-bridge.service` | `~/.config/systemd/user/ccpocket-bridge.service` | Persistent authenticated CC Pocket Bridge service. |
| `ccpocket/start-bridge` | `~/.local/bin/start-ccpocket-bridge` | Launches the installed Bridge in the active Node environment without printing pairing credentials in service logs. |
| `ccpocket/pair` | `~/.local/bin/ccpocket-pair` | Displays a local pairing QR and saves it to `~/.ccpocket/pairing.png`. |
| `ccpocket/bridge.env.example` | *(local configuration template)* | Bridge address, workspace scope and Claude authentication opt-in. The real key stays in `~/.config/ccpocket/bridge.env`. |
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

`install.sh` installs the paths marked as linked or copied above. If a real file already
exists at a target, it's backed up to `<path>.bak-<timestamp>` first — safe
to re-run any time. It also runs `systemctl --user daemon-reload` if
`systemctl` is available.

Codex's `config.toml` remains a regular machine-local file because it also stores project trust and generated state. Installation copies the personal defaults only when the file is absent and preserves an existing configuration. The full desktop snapshot lives in `codex/profiles/desktop.toml`; review local paths and trust entries before restoring it on another machine. To refresh that snapshot from the desktop, copy `~/.codex/config.toml` to `codex/profiles/desktop.toml`.

The Codex launcher requires Node and npm, normally provided by nvm, and an installed `@openai/codex` package in the active Node environment. Installation links configuration and scripts; it does not install or update agent binaries.

Once you've confirmed the symlinked config works, remove the backups:

```bash
~/workspace/tmux-agent-config/install.sh --clean-backups
```

This finds every `<path>.bak-*` left by past installs and deletes them after
a confirmation prompt — no need to hunt them down by hand on each machine.

## Per-machine session setup

To link the saved desktop definitions without starting or restarting any session:

```bash
~/workspace/tmux-agent-config/install.sh --sessions desktop
```

After checking workspace paths, restore the enabled desktop services explicitly:

```bash
while IFS= read -r session_name; do
    systemctl --user enable --now "ai-session@${session_name}.service"
done < ~/workspace/tmux-agent-config/ai-sessions/profiles/desktop/enabled-sessions.txt
systemctl --user enable --now codex-remote-control.service
```

The systemd unit and watcher script are generic, but *which* sessions run is
per-machine (different projects live on different boxes). For each session:

```bash
cp ai-sessions/env.example ~/.config/ai-sessions/<device>-<foldername>-<agent>.env
# edit CWD and AGENT in it
systemctl --user enable --now ai-session@<device>-<foldername>-<agent>.service
```

Session names follow `<device>-<foldername>-<agent>` (see `CLAUDE.md`):
`device` is `desktop` or `laptop`, `foldername` is the working directory's
basename, `agent` is `claude`, `copilot`, or `codex`. This keeps the tmux session name,
the systemd instance name, and the Claude Code `--rc` remote-control title in
sync so sessions are recognizable from FleetView / Remote Control on Android.

## What's deliberately *not* here

- Unrecorded `~/.config/ai-sessions/*.env` — per-machine definitions; saved desktop definitions live in `ai-sessions/profiles/desktop/`.
- `~/.claude.json`, `~/.claude/.credentials.json` — session/auth state, not config.
- `~/.codex/auth.json`, conversation databases, transcripts, logs and `~/.local/state/ai-sessions/` UUID mappings — credentials and runtime state.
- Anything under `~/.claude/projects/` (including the memory system) — conversation history and learned memory, not portable setup.

## CC Pocket Bridge

Install the Node package and link the service and commands:

```bash
npm install -g @ccpocket/bridge@1.88.0
./install.sh
```

Create the private local configuration from `ccpocket/bridge.env.example`, use your machine's Meshnet or LAN address and allowed home directory, and generate a pairing key:

```bash
install -d -m 700 ~/.config/ccpocket
install -m 600 ccpocket/bridge.env.example ~/.config/ccpocket/bridge.env
node -e 'console.log(require("node:crypto").randomBytes(32).toString("base64url"))'
```

Set `BRIDGE_API_KEY` to that generated value. Keep the file local; it is not committed. Codex uses the machine's existing login. Claude subscription authentication is disabled unless you explicitly set `BRIDGE_ALLOW_CLAUDE_OAUTH=1`; see the [upstream Bridge documentation](https://github.com/K9i-0/ccpocket/blob/main/packages/bridge/README.md).

The desktop uses `BRIDGE_ALLOWED_DIRS=/home/julien`, allowing sessions in the home directory and all its descendants, including `~/workspace`. This scope also includes hidden configuration and credential directories; access requires the bridge pairing key.

Start the service and display the pairing QR:

```bash
systemctl --user enable --now ccpocket-bridge.service
ccpocket-pair
```

The desktop's advertised endpoint is `ws://100.121.101.37:8765`, its NordVPN Meshnet address (`julien-desktop-meshnet`). Enable Meshnet on the phone under the same Nord account, then enter that endpoint and the bridge key in CC Pocket or scan the pairing QR. Linked devices need permission to access the desktop remotely. Meshnet provides the private route when away from home; see the [Meshnet remote-access guide](https://meshnet.nordvpn.com/how-to/joint-projects/nginx-web-server-access).

The home-LAN endpoint `ws://192.168.77.2:8765` also remains available while on that network. The QR includes the authentication key and uses `BRIDGE_PUBLIC_WS_URL` from the local configuration. Regenerate it with `ccpocket-pair` after changing the key or address.

Use `systemctl --user restart ccpocket-bridge` after configuration or package updates, and `systemctl --user status ccpocket-bridge` or `journalctl --user -u ccpocket-bridge` to inspect it. `update-ai-clis` updates the installed Bridge package without restarting active sessions.

On this desktop, CC Pocket connects to the existing Codex app/IDE daemon using `BRIDGE_CODEX_APP_SERVER_MODE=external` and a `ws+unix://<socket-path>:/` URL in the private local environment file. Codex's Unix endpoint accepts WebSocket connections; CC Pocket's WebSocket client supports this local transport. Sharing the same daemon lets CC Pocket resume threads owned by that daemon without creating a competing writer. The launcher ensures the daemon is running before starting the Bridge. Locate the active control socket with `ss -lxnp`; it is under `/tmp/codex-daemon-<uid>/`. This connection remains local; the phone continues to use the authenticated Meshnet bridge endpoint.

This integration has been verified with Codex 0.160.0 and Bridge 1.88.0. Threads owned by an independent Codex process still require a handoff. For a terminal client joining the desktop daemon, use `codex resume <thread-id> --remote unix://`.

For CC Pocket's SSH start/stop controls on the desktop, use host `100.121.101.37`, port `22`, username `julien`, and private-key authentication. The dedicated phone key is `~/.ssh/ccpocket-phone.pem`, in RSA PEM format with no passphrase; its public key is authorized on the desktop. Import that private file into the phone's SSH credentials. Private keys and `authorized_keys` remain outside this repository. The service's explicit `/bin/bash` launcher supports CC Pocket's SSH startup preflight.

### Codex conversation persistence

Codex services use `ai-sessions/ai-session-codex`, located beside the watcher
(the watcher symlink resolves to this repository). Python 3 is required. Claude
keeps its existing resume behavior. Codex UUIDs are saved in
`~/.local/state/ai-sessions/<service-name>.codex-id`; keep these files across
restarts. The helper reads Codex's local thread database without modifying it.
On first launch it adopts a matching named conversation, or the most recent
unclaimed conversation in a workspace used by only one Codex service. Shared
workspaces start separate conversations and track their own process files.
Fresh conversations are recorded once Codex creates the thread; folder trust
prompts must be accepted before that can happen. Missing or archived saved
conversations fail explicitly rather than silently losing history.

The Codex helper keeps monitoring the launched TUI and its descendants via Linux
`/proc`. It follows newly opened interactive rollout files after `/clear` or
`/new`, updating the service UUID while excluding other services and subagents.
Previous conversations remain saved in Codex but are not resumed by this service.

### Copilot conversation persistence

Copilot services use the adjacent `ai-sessions/ai-session-copilot` helper
(Python 3). It saves the foreground conversation UUID in
`~/.local/state/ai-sessions/<service-name>.copilot-id` and resumes that exact
conversation. Initial named-session lookup reads `workspace.yaml` for sessions
indexed in Copilot's database, rather than relying on `session_refs` names.
The helper follows foreground registration messages in isolated per-launch
process logs under `<service-name>.copilot-logs/`, including `/clear`, `/new`,
and `/resume`. It waits for previous session holders to exit before resuming.
Missing saved conversations fail explicitly. Copilot's database and transcripts
are not modified by the helper. The watcher resolves both Python helpers next
to its repository source, so the existing installer symlink includes them.

Codex AI services launch with `--sandbox danger-full-access --ask-for-approval
never` for full access without approval prompts. Copilot services launch with
`--yolo --remote`. Codex remote control uses the enabled user daemon service.

Codex entries with no rollout or recorded turns start fresh on restart. The helper also tracks open thread-writer locks for
paginated history, which may not have a legacy rollout file. An empty saved
conversation never falls back to an older conversation from before `/clear`.

Interactive Codex recovery includes CLI and VS Code conversations. If a saved
UUID is empty, a service with a unique workspace may adopt a newer populated
conversation in that workspace (for example one created in VS Code). It never
adopts a conversation older than that empty UUID, preserving `/clear` semantics.
Services sharing a workspace retain their separate UUID mappings.

Codex conversation discovery uses `thread_source=user` rather than the mutable
client `source` label. Opening a conversation through another client must not
exclude its UUID from recovery; guardian threads remain excluded.
