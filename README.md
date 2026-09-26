# bb-app on the homelab

Self-hosted [bb](https://getbb.app/) (the agent IDE), exposing the **Pi
provider only**, reachable **only over the tailnet** using the same
tailscale-sidecar pattern as `~/Dev/foundry-vtt-container` and `~/Dev/n8n`.
No funnel, no published host ports — the web UI is available only at
`https://<app>.<your-tailnet>.ts.net` while you're on the tailnet.

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

It also installs the upstream **GitHub CLI** (`gh`) release `.deb`, pinned via
the `GH_VERSION` / `GH_SHA256_AMD64` build args. The base image's Debian
bookworm `gh` is fixed at 2.23.0 (Feb 2023), so we override it with a
checksum-verified upstream build instead of cli.github.com's apt repo (which
would pull in `gnupg`).

To bump it later: update `GH_VERSION` and `GH_SHA256_AMD64` from
`gh_<version>_checksums.txt` on the [releases page](https://github.com/cli/cli/releases),
then rebuild.

```bash
# get the new sha for your arch
curl -sSL https://github.com/cli/cli/releases/download/v<NEW>/gh_<NEW>_checksums.txt \
  | grep linux_amd64.deb
```

## Run

Fill `.env` (`TAILSCALE_AUTH_KEY`, `BB_APP_IMAGE`, `BB_APP_PORT`), then:

```bash
docker compose up -d --build
docker compose logs -f bb-app
```

Verify over the tailnet:

```bash
tailscale status | grep bb-app
curl -sI https://<app>.<your-tailnet>.ts.net
```

## Pi config: two repos, split by ownership

On every start the entrypoint syncs `~/.pi` from two repos. Each owns a
disjoint slice, so neither can clobber the other.

| Layer | Source repo | Paths |
| --- | --- | --- |
| Runtime config | [`rcopeland/dotfiles`](https://github.com/rcopeland/dotfiles) | `settings.json`, `mcp.json`, `extensions/`, `themes/` |
| Agent config | [`RCopeland/ai-docs`](https://github.com/RCopeland/ai-docs) | `agents/`, `skills/`, `AGENTS.md` |

The dotfiles sync uses a **lightweight git copy of just `.pi`** rather than a
full `yadm clone`, because the dotfiles' `bootstrap` targets host package
managers (pacman/brew/KDE) that don't belong in a slim container.

The ai-docs sync maps its flatter layout onto Pi's paths: its `agents/` and
`skills/` land in `~/.pi/agent/`, and its `global/AGENTS.md` becomes
`~/.pi/agent/AGENTS.md`. It **removes** those trees before copying, so deletions
upstream actually propagate (a plain copy-over never deletes anything).

Secrets (`auth.json`, `sessions/`) are in neither repo, so they survive syncs
in the persisted home volume.

### Environment variables

| Variable | Purpose |
| --- | --- |
| `BB_APP_DOTFILES_REPO` | Override the dotfiles repo URL. |
| `BB_SYNC_DOTFILES=0` | Skip the dotfiles sync. |
| `BB_APP_AI_DOCS_REPO` | Override the ai-docs repo URL. |
| `BB_SYNC_AI_DOCS=0` | Skip the ai-docs sync. |

### Retired: ai-config symlinks

The entrypoint also **removes** any leftover `ai-config` symlinks at
`~/.pi/agent/{agents,skills,AGENTS.md,agent-models.json}`. A previous setup
symlinked those paths into a local `~/Dev/ai-config` checkout; that repo is
retired. Leaving the links in place would shadow the synced files above and
resurrect deleted config, so boot breaks them unconditionally.

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