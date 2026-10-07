# CC Pocket Bridge

The authenticated Bridge runs as a user service. The global Caddy instance in `../reverse-proxy/` provides its public WSS endpoint on port `8765`, alongside HTTPS access to the Sunder Forge wiki and other routed services.

Set `BRIDGE_PUBLIC_WS_URL=wss://julienlavergne.asuscomm.com:8765` in the private `~/.config/ccpocket/bridge.env`. Keep `BRIDGE_API_KEY` configured. The local Bridge continues listening on port `8765`; the router sends public port `8765` to Caddy's host port `18765` instead of directly to the Bridge.

The router forwards public TCP `80` to host port `18080`, public TCP `443` to host port `18443`, and public TCP `8765` to host port `18765`. Caddy runs in WSL's Docker bridge network and uses only those high host ports, leaving host ports `80` and `443` unused. Caddy uses the ASUS router's exported certificate from `~/.config/caddy/certs/cert.pem` and `key.pem`; after the router renews its certificate, replace these files and restart Caddy.

The WSL egress policy in `../reverse-proxy/` routes replies for those inbound Caddy ports through the normal LAN gateway. Other WSL traffic keeps its VPN route.

Start Caddy from the repository root:

```sh
docker compose -f reverse-proxy/compose.yaml up -d
```

For direct Meshnet access, use `ws://julien-desktop-meshnet:8765` with the Bridge API key. This reaches the Bridge directly and bypasses Caddy; the firewall allows TCP 8765 only from Meshnet addresses in `100.64.0.0/10`. For public access, use `wss://julienlavergne.asuscomm.com:8765` through Caddy. Regenerate the pairing QR with `ccpocket-pair` after changing the public URL or pairing key.
