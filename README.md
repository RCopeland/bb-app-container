# bb-app on the homelab

Self-hosted [bb](https://getbb.app/) (the agent IDE), exposing the **Pi
provider only**, reachable **only over the tailnet** using the same
tailscale-sidecar pattern as `~/Dev/foundry-vtt-container` and `~/Dev/n8n`.
No funnel, no published host ports — the web UI is available only at
`https://bb-app.tail4fde5e.ts.net` while you're on the tailnet.

## How it works

- A **tailscale sidecar** joins the tailnet as host `bb-app`, provisions an
  HTTPS cert, and runs `tailscale serve` from `ts-serve.json` (no
  `AllowFunnel` → tailnet-only).
- **`bb-app` shares the sidecar's namespace** (`network_mode:
  service:tailscale`), binding `127.0.0.1:38886`. It is not published on the
  host, so nothing on the LAN/internet can reach it.
- `ts-serve.json` proxies `443` → `127.0.0.1:${BB_APP_PORT}` for
  `${TS_CERT_DOMAIN}`.

## Building the image (local — no official image exists)

bb is an npm launcher, not a container. `Dockerfile` builds `bb-app:local`:

```bash
docker build -t bb-app:local .
```

The image installs `bb-app` **and** `@earendil-works/pi-coding-agent` (the CLI
bb's Pi provider drives via `pi --mode rpc`).

## Run

Fill `.env` (`TAILSCALE_AUTH_KEY`, `BB_APP_IMAGE`, `BB_APP_PORT`), then:

```bash
docker compose up -d --build
docker compose logs -f bb-app
```

Verify over the tailnet:

```bash
tailscale status | grep bb-app
curl -sI https://bb-app.tail4fde5e.ts.net
```

## Pi config: from your dotfiles

On every start the entrypoint `sync`s `~/.pi` from
`https://github.com/rcopeland/dotfiles` (settings.json, mcp.json, extensions,
skills, themes, agents, agent-models.json). It uses a **lightweight git copy of
just `.pi`** rather than full `yadm clone`, because the dotfiles' `bootstrap`
targets host package managers (pacman/brew/KDE) that don't belong in a slim
container. Secrets (`auth.json`, `sessions/`) aren't in the repo, so they
survive syncs.

- Point it elsewhere: set `BB_APP_DOTFILES_REPO` in the container env.
- Skip the sync: set `BB_SYNC_DOTFILES=0`.

## Pi auth (first time)

bb's Pi provider needs Pi signed in. Do it once in-browser against the running
container (writes `~/.pi/agent/auth.json` into the persisted home volume):

```bash
docker compose exec bb-app pi
# in pi: /login, pick your provider (openai-codex / codex subscription), approve
```

The credential persists in `bb_app_home`, not in the image or compose. Rotate
it the same way you would any API key.

## Security notes

- The bb server API is **unauthenticated and can run commands/read files**;
  it is safe here only because it's behind the tailnet (no funnel/ports). Do
  **not** add ports or funnel.
- A compromise of this container exposes both your code (`~/Dev` is mounted
  read/write) and your signed-in Pi credential — treat the box as trusted
  infra, keep it patched, and rotate Pi's credential periodically.

## Files

| File              | Purpose                                    |
|-------------------|--------------------------------------------|
| `Dockerfile`      | local bb-app + Pi image build              |
| `entrypoint.sh`   | sync dotfiles `.pi` + start bb             |
| `compose.yaml`    | tailscale sidecar + bb-app                 |
| `ts-serve.json`   | `tailscale serve` config (tailnet-only)    |
| `.env`/`.env.example` | secrets/config                         |