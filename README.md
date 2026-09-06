# bb-app on the homelab

Self-hosted `bb-app`, exposed **only over the tailnet** using the same
tailscale-sidecar pattern as `~/Dev/foundry-vtt-container` and `~/Dev/n8n`.
No funnel, no published host ports — the app is reachable solely at
`https://bb-app.tail4fde5e.ts.net` (and only while you're connected to the
tailnet).

## How it works

- A **tailscale sidecar** (`tailscale/tailscale:latest`) joins the tailnet as
  host `bb-app`. It runs `tailscale cert` (HTTPS) and `tailscale serve` using
  `ts-serve.json`.
- **`bb-app` shares the sidecar's network namespace**
  (`network_mode: service:tailscale`), so it binds on loopback
  (`127.0.0.1:BB_APP_PORT`) inside that namespace. It is *not* published on
  the host, so nothing on the LAN or internet can reach it.
- `ts-serve.json` proxies `443` → `127.0.0.1:${BB_APP_PORT}` for
  `${TS_CERT_DOMAIN}`. There is **no `AllowFunnel`**, matching the n8n stack —
  tailnet-only, as intended.

## Setup

1. Copy `.env.example` to `.env` and fill in:
   - `TAILSCALE_AUTH_KEY` — a tailnet auth key (reuse the foundry one or mint
     a fresh node key).
   - `BB_APP_IMAGE` — the real image ref for bb-app.
   - `BB_APP_PORT` — the port bb-app listens on inside the container
     (default 8080).
2. Bring it up:
   ```bash
   cd /home/rob/Dev/bb-app-container
   docker compose up -d
   ```
3. Verify the MagicDNS name resolves and serves over the tailnet:
   ```bash
   tailscale status | grep bb-app
   curl -sI https://bb-app.tail4fde5e.ts.net
   ```

## Troubleshooting

- **`${BB_APP_IMAGE:?set BB_APP_IMAGE in .env}`** → edit `.env`.
- **Cert not provisioned** → first HTTPS request may need a few seconds while
  `tailscale cert` issues the domain cert; check `docker logs bb-app-tailscale`.
- **Port mismatch** → ensure `BB_APP_PORT` matches both the app's real listen
  port and `ts-serve.json` (it's substituted from the sidecar's env).

## Files

| File            | Purpose                                        |
|-----------------|------------------------------------------------|
| `compose.yaml`  | tailscale sidecar + bb-app service             |
| `ts-serve.json` | `tailscale serve` config (tailnet-only)        |
| `.env`/`.env.example` | secrets/config                          |