# AI agent network namespace

Claude, Codex, Copilot, the CCPocket Bridge, and the shared Codex app-server run in the dedicated `agent-wg` Linux network namespace. Its default route uses the Freebox WireGuard interface. A private veth connects the namespace to Caddy for the Bridge's inbound WebSocket port; host firewall and source-NAT rules allow only that forwarded connection. The WireGuard interface is created in the WSL host namespace and then moved into the namespace, while its encrypted UDP transport stays on the host. A temporary host route sends only the Freebox endpoint packets over the normal WSL LAN interface.

The Freebox client profile is private and remains at `~/.config/wireguard/freebox-agent.conf` with mode `600`. It is not tracked in Git. The profile is full-tunnel for IPv4 and has `PersistentKeepalive = 25` on the client peer. It has no IPv6 default route, so IPv6-only destinations will fail inside the sandbox rather than bypass the tunnel.

The private Caddy veth addresses and Bridge bind address live in `wireguard-agent/network.env`, installed as `/etc/agent-wg/network.env`. Change the veth subnet there if it ever overlaps another local network, then rerun the installer before the next activation.

Run `sudo ./wireguard-agent/install-agent-wg.sh` to install the disabled system service and the restricted process launcher. The installer does not enable or start the tunnel. Later, after reviewing the profile and choosing to connect, start it with:

```sh
sudo systemctl start agent-wg-sandbox.service
```

Desktop CLI session profiles use `NETWORK_NAMESPACE=agent-wg`. The namespace must be active before a CLI can connect; the launcher fails closed when it is unavailable.

When the namespace is active, `agent-wg-run -- <command> [args...]` runs a command as Julien inside it. Use `agent-wg-run --inherit-env -- <command> [args...]` for services that need selected provider or application settings; the launcher passes only Bridge, Claude, AWS, Codex, OpenAI, and proxy variables. Windows executables are unavailable inside the namespace, preventing WSL interop processes from escaping onto the Windows network. The namespace isolates networking, not filesystem access.

The shared Codex app-server runs under `codex-remote-control-agent-wg.service`. The CCPocket Bridge service also runs inside `agent-wg` and connects to that daemon through the configured `ws+unix://` socket. The socket remains accessible because the services share the WSL filesystem. The Bridge binds to the private veth address defined in `network.env`; Caddy remains outside the namespace, terminates public TLS on port 8765, and forwards traffic across the veth. A second Caddy listener exposes `ws://julien-desktop-meshnet:8765` only to Meshnet clients.

Start `agent-wg-sandbox.service` before starting the Codex Remote Control and CCPocket Bridge user services. Then run `systemctl --user start codex-remote-control-agent-wg.service ccpocket-bridge.service`. The installer does not activate the tunnel or start either user service.

After turning NordVPN off, finish the move from a separate WSL terminal with:

```sh
agent-wg-transition activate
```

The script checks the WireGuard egress and Caddy path, moves the shared Codex daemon and Bridge, then restarts the AI sessions with `desktop-home-codex` last. If activation fails during cutover, it attempts to restore host mode automatically. To request that recovery directly, run `agent-wg-transition recover` from a separate WSL terminal. Recovery restores the host Bridge, Codex daemon, Caddy route, and host-network session profiles.
