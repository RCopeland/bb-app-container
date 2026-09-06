# syntax=docker/dockerfile:1
# bb-app (agent IDE) + the Pi provider only, for the x86_64 homelab.
# Clientless: no GUI; reached through the tailscale sidecar's `serve`.
FROM node:22.19.0-bookworm-slim

ENV DEBIAN_FRONTEND=noninteractive \
    NODE_ENV=production \
    HOME=/home/node \
    BB_TELEMETRY=false

# Native deps (better-sqlite3, node-pty, @parcel/watcher) need a build toolchain.
# yadm/git available but entrypoint uses a lightweight .pi sync by default.
RUN apt-get update \
    && apt-get install -y --no-install-recommends \
        python3 make g++ git ca-certificates curl yadm \
    && rm -rf /var/lib/apt/lists/*

# bb launcher + the Pi coding agent (used by bb's Pi provider bridge, `pi --mode rpc`).
# Pin pi to a known-good version; provider requires >=0.84.0.
RUN npm i -g --allow-scripts=better-sqlite3,node-pty,@parcel/watcher bb-app@latest \
    && npm i -g @earendil-works/pi-coding-agent@0.85.1

# Runtime home: created and owned by "node". Container runs as root so the
# bind-mounted host ~/Dev is fully accessible to agents.
RUN mkdir -p /home/node/Dev \
    && chown -R node:node /home/node

COPY entrypoint.sh /usr/local/bin/bb-entrypoint.sh
RUN chmod +x /usr/local/bin/bb-entrypoint.sh

WORKDIR /home/node
EXPOSE 38886

ENTRYPOINT ["/usr/local/bin/bb-entrypoint.sh"]
CMD ["bb-app"]