# AI agent network namespace

The `agent-wg` Linux namespace uses the Freebox WireGuard interface as its default route. The current transition moves the shared Codex app-server and `desktop-home-codex` into it; other sessions and the CCPocket Bridge remain on the host. A private veth and restricted Caddy forwarding path are configured for a later Bridge move. The WireGuard interface is created in the WSL host namespace and then moved into the namespace, while its encrypted UDP transport stays on the host. A temporary host route sends only the Freebox endpoint packets over the normal WSL LAN interface.

The Freebox client profile is private and remains at `~/.config/wireguard/freebox-agent.conf` with mode `600`. It is not tracked in Git. The profile is full-tunnel for IPv4 and has `PersistentKeepalive = 25` on the client peer. It has no IPv6 default route, so IPv6-only destinations will fail inside the sandbox rather than bypass the tunnel.

The private Caddy veth addresses and Bridge bind address live in `wireguard-agent/network.env`, installed as `/etc/agent-wg/network.env`. Change the veth subnet there if it ever overlaps another local network, then rerun the installer before the next activation.

Run `sudo ./wireguard-agent/install-agent-wg.sh` to install the disabled system service and the restricted process launcher. The installer does not enable or start the tunnel. Later, after reviewing the profile and choosing to connect, start it with:

```sh
sudo systemctl start agent-wg-sandbox.service
```

The `desktop-home-codex` profile uses `NETWORK_NAMESPACE=agent-wg`; other desktop session profiles remain on the host for now. The namespace must be active before a CLI can connect; the launcher fails closed when it is unavailable.

When the namespace is active, `agent-wg-run -- <command> [args...]` runs a command as Julien inside it. Use `agent-wg-run --inherit-env -- <command> [args...]` for services that need selected provider or application settings; the launcher passes only Bridge, Claude, AWS, Codex, OpenAI, and proxy variables. Windows executables are unavailable inside the namespace, preventing WSL interop processes from escaping onto the Windows network. The namespace isolates networking, not filesystem access.

The shared Codex app-server runs under `codex-remote-control-agent-wg.service`. The host CCPocket Bridge connects to it through the configured `ws+unix://` socket, which remains accessible because the services share the WSL filesystem. Caddy and the Bridge stay on the host during this cutover.

The installer does not activate the tunnel or start user services. The transition script starts the namespace and Codex daemon, then restarts only `desktop-home-codex`.

After turning NordVPN off, finish the move from a separate WSL terminal with:

```sh
agent-wg-transition activate
```

The script checks WireGuard egress, moves the shared Codex daemon, and restarts only `desktop-home-codex`. CCPocket Bridge, Caddy, and other sessions stay on the host. If activation fails, it attempts to restore this session and daemon to host mode. To request that recovery directly, run `agent-wg-transition recover` from a separate WSL terminal.
