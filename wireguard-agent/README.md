# Claude/Codex WireGuard namespace

This runs selected Claude and Codex CLI sessions in a dedicated Linux network namespace. The namespace has only loopback and the Freebox WireGuard interface, so its default route cannot fall back to the host's VPN or LAN. The WireGuard interface is created in the WSL host namespace and then moved into the sandbox; its encrypted UDP transport remains in the host namespace. A temporary route sends only the Freebox endpoint packets over the normal WSL LAN interface.

The Freebox client profile is private and remains at `~/.config/wireguard/freebox-agent.conf` with mode `600`. It is not tracked in Git. The profile is full-tunnel for IPv4 and has `PersistentKeepalive = 25` on the client peer. It has no IPv6 default route, so IPv6-only destinations will fail inside the sandbox rather than bypass the tunnel.

Run `sudo ./wireguard-agent/install-agent-vpn.sh` to install the disabled system service and the restricted process launcher. The installer does not enable or start the tunnel. Later, after reviewing the profile and choosing to connect, start it with:

```sh
sudo systemctl start agent-vpn-sandbox.service
```

To opt one Claude/Codex CLI session into the sandbox, add `NETWORK_NAMESPACE=agent-vpn` to that session's `~/.config/ai-sessions/<name>.env` and restart that session. Existing sessions and profiles remain on the host network by default. Copilot sessions are not supported by the namespace launcher.

When the namespace is active, `agent-vpn-run -- <command> [args...]` runs a command as Julien inside it. Windows executables are deliberately unavailable there, preventing WSL interop processes from escaping onto the Windows network. The namespace isolates networking, not filesystem access. The shared Codex app-server has a separate optional unit, `codex-remote-control-agent-vpn.service`, so its model traffic can also use the tunnel. The installer only installs that unit; it does not start or enable it.
