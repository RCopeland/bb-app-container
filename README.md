# bb-app on the homelab

Self-hosted [bb](https://getbb.app/) (the agent IDE), exposed **only over the
tailnet** using the same tailscale-sidecar pattern as
`~/Dev/foundry-vtt-container` and `~/Dev/n8n`. No funnel, no published host
ports — the UI is reachable **only at `https://bb-app.tail4fde5e.ts.net`**
while you're connected to the tailnet.

## Important — how bb-app is distributed

There is **no official bb Docker image**. bb is a Node.js runtime distributed
as an npm launcher (`npx bb-app@latest`):

- It runs a **central server + host daemon + web app**, serving the UI on
  **port `38886`**.
- It needs **native add-ons** (`better-sqlite3`, `node-pty`, `@parcel/watcher`),
  so the container must build them (needs a full node image + build toolchain).
- It runs agents through **provider CLIs** (Claude Code, Codex, Pi, Cursor,
  OpenCode, Grok…) using **your own API keys**, stored under `~/.bb/`.

So this stack is built from a local `Dockerfile` (image `bb-app:local`), not
pulled from a registry.

## How it works

- A **tailscale sidecar** (`tailscale/tailscale:latest`) joins the tailnet as
  host `bb-app`. It provisions an HTTPS cert and runs `tailscale serve` from
  `ts-serve.json`.
- **`bb-app` shares the sidecar's network namespace**
  (`network_mode: service:tailscale`), binding on `127.0.0.1:38886`. It is
  *not* published on the host, so nothing on the LAN or internet can reach it.
- `ts-serve.json` proxies `443` → `127.0.0.1:${BB_APP_PORT}` for
  `${TS_CERT_DOMAIN}`. There is **no `AllowFunnel`** — tailnet-only, by design.
- This matches bb's own security guidance: the server API is unauthenticated
  and can run commands/read files, so it must live behind a trusted network
  boundary (the tailnet) — no public exposure.

## Build & run

1. Copy `.env.example` to `.env` and set:
   - `TAILSCALE_AUTH_KEY` — a tailnet auth key (reuse the foundry one or mint a
     new node key).
   - `BB_APP_PORT` — `38886` (bb's web UI port).
   - `BB_APP_IMAGE` — `bb-app:local` (built from the `Dockerfile`).
2. Build the image:
   ```bash
   docker build -t bb-app:local .
   ```
3. Bring it up:
   ```bash
   docker compose up -d
   ```
4. Verify over the tailnet:
   ```bash
   tailscale status | grep bb-app
   curl -sI https://bb-app.tail4fde5e.ts.net
   ```

## Provider CLIs & credentials

For bb to actually run agents **inside this container**, the provider CLIs you
use must be installed in the image **and** authenticated with your keys. These
are deliberately **not** baked into the committed `Dockerfile` (they're
secrets). Decide which providers you need, then see the provider section of the
`Dockerfile` and configure keys via:
- env vars (e.g. `ANTHROPIC_API_KEY`) passed in `compose.yaml`, or
- the mounted `~/.bb` data dir (`env.json` / `config.json`), persisted in the
  `bb_app_data` volume.

Projects/repos bb should work on must be **mounted into the container** too
(e.g. a read-write `hostPath` of `~/Dev`), otherwise the container has nowhere
to operate.

## Files

| File              | Purpose                                  |
|-------------------|------------------------------------------|
| `Dockerfile`      | Local bb-app image build (npm launcher)  |
| `compose.yaml`    | tailscale sidecar + bb-app service       |
| `ts-serve.json`   | `tailscale serve` config (tailnet-only)  |
| `.env`/`.env.example` | secrets/config                       |

## Privacy note

bb sends anonymous usage telemetry by default. Opt out by setting
`BB_TELEMETRY=false` in the container environment (see `compose.yaml`).