#!/bin/sh
# bb-app container entrypoint:
#   1. (optional) sync ~/.pi from the dotfiles repo (keeps config current,
#      never touches secrets like auth.json/sessions since they're not in repo)
#   2. ensure runtime dirs exist
#   3. exec bb-app (server + host daemon + web on :38886)
set -e
DOTFILES_REPO="${BB_APP_DOTFILES_REPO:-https://github.com/rcopeland/dotfiles}"

if [ "${BB_SYNC_DOTFILES:-1}" != "0" ]; then
  echo ">> syncing ~/.pi from $DOTFILES_REPO"
  tmp="$(mktemp -d)"
  if git -c http.lowSpeedLimit=1000 -c http.lowSpeedTime=20 \
        clone --depth 1 "$DOTFILES_REPO" "$tmp" >/dev/null 2>&1; then
    mkdir -p "$HOME/.pi"
    # Bring over tracked pi config (settings, mcp, extensions, skills, themes,
    # agents, agent-models). auth.json / sessions / logs are NOT in the repo,
    # so they survive across syncs (persisted in the home volume).
    cp -a "$tmp/.pi/." "$HOME/.pi/" 2>/dev/null || true
    rm -rf "$tmp"
    echo ">> .pi synced"
  else
    echo "!! dotfiles clone failed ($DOTFILES_REPO); continuing with existing ~/.pi"
    rm -rf "$tmp"
  fi
else
  echo ">> dotfiles sync disabled (BB_SYNC_DOTFILES=0)"
fi

mkdir -p "$HOME/.bb" "$HOME/Dev"

echo ">> starting bb-app (web on :38886, Pi provider)"
exec "$@"