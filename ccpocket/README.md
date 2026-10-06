# Public CC Pocket access

Caddy terminates HTTPS for the public CC Pocket endpoint and forwards WebSocket traffic to the local Bridge. The Bridge keeps its API-key authentication and existing Codex app-server connection.

## Router setup

Forward TCP ports `80` and `443` to the WSL LAN address `192.168.77.2`. Remove the public TCP `8765` forward after the HTTPS endpoint has been verified. Keep `8765` available on trusted local interfaces for direct home-Wi-Fi access if desired.

WSL uses mirrored networking and has its own LAN address, so a Windows `netsh portproxy` rule is not required for this setup.

## Start and verify

From this directory, start Caddy with:

```sh
docker compose up -d
```

Use `wss://julienlavergne.asuscomm.com` as the CC Pocket Bridge URL. Caddy obtains and renews the TLS certificate automatically. Persisted certificate state is kept in Docker volumes.

For direct home-Wi-Fi access, CC Pocket can use mDNS or `ws://192.168.77.2:8765`. Use the HTTPS domain for internet access.

Keep `BRIDGE_API_KEY` configured in `~/.config/ccpocket/bridge.env`. The public router must not forward TCP `8765` directly to the Bridge.
