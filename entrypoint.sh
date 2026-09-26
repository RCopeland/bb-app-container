#!/bin/sh
# bb-app container entrypoint:
#   1. (optional) sync ~/.pi runtime config from the dotfiles repo
#      (settings, mcp, extensions, themes). Never touches secrets like
#      auth.json/sessions since they're not in the repo.
#   2. (optional) sync the agent roster, skills, and global AGENTS.md from
#      the ai-docs repo (the authoritative source for those).
#   3. replace any stale ai-config symlinks with real files so a retired
#      local config checkout cannot resurrect deleted config.
#   4. ensure runtime dirs exist
#   5. exec bb-app (server + host daemon + web on :38886)
#
# Ownership split:
#   dotfiles -> settings.json, mcp.json, extensions/, themes/
#   ai-docs  -> agents/, skills/, global AGENTS.md
set -e
DOTFILES_REPO="${BB_APP_DOTFILES_REPO:-https://github.com/rcopeland/dotfiles}"
AI_DOCS_REPO="${BB_APP_AI_DOCS_REPO:-https://github.com/RCopeland/ai-docs}"

# Fetch a shallow clone of $1 into a temp dir; echo the path on success.
clone_repo() {
  _tmp="$(mktemp -d)"
  if git -c http.lowSpeedLimit=1000 -c http.lowSpeedTime=20 \
        clone --depth 1 "$1" "$_tmp" >/dev/null 2>&1; then
    printf '%s' "$_tmp"
  else
    rm -rf "$_tmp"
    return 1
  fi
}

# --- 1. dotfiles: Pi runtime config -----------------------------------------
if [ "${BB_SYNC_DOTFILES:-1}" != "0" ]; then
  echo ">> syncing ~/.pi runtime config from $DOTFILES_REPO"
  if tmp="$(clone_repo "$DOTFILES_REPO")"; then
    mkdir -p "$HOME/.pi"
    # auth.json / sessions / logs are NOT in the repo, so they survive syncs
    # (they live in the persisted home volume).
    cp -a "$tmp/.pi/." "$HOME/.pi/" 2>/dev/null || true
    rm -rf "$tmp"
    echo ">> .pi runtime config synced"
  else
    echo "!! dotfiles clone failed ($DOTFILES_REPO); continuing with existing ~/.pi"
  fi
else
  echo ">> dotfiles sync disabled (BB_SYNC_DOTFILES=0)"
fi

# --- 2. ai-docs: agents, skills, global AGENTS.md ---------------------------
# ai-docs uses a flat layout (agents/, skills/, global/AGENTS.md), so map it
# onto Pi's expected paths under ~/.pi/agent/.
if [ "${BB_SYNC_AI_DOCS:-1}" != "0" ]; then
  echo ">> syncing agents/skills/AGENTS.md from $AI_DOCS_REPO"
  if tmp="$(clone_repo "$AI_DOCS_REPO")"; then
    agent_dir="$HOME/.pi/agent"
    mkdir -p "$agent_dir"

    # Remove existing trees first so deletions upstream actually propagate
    # (a plain copy-over never removes anything).
    for item in agents skills; do
      if [ -e "$agent_dir/$item" ] || [ -L "$agent_dir/$item" ]; then
        rm -rf "$agent_dir/$item"
      fi
    done
    if [ -e "$agent_dir/AGENTS.md" ] || [ -L "$agent_dir/AGENTS.md" ]; then
      rm -rf "$agent_dir/AGENTS.md"
    fi

    [ -d "$tmp/agents" ] && cp -a "$tmp/agents" "$agent_dir/agents"
    [ -d "$tmp/skills" ] && cp -a "$tmp/skills" "$agent_dir/skills"
    [ -f "$tmp/global/AGENTS.md" ] && cp -a "$tmp/global/AGENTS.md" "$agent_dir/AGENTS.md"

    rm -rf "$tmp"
    echo ">> agents, skills, and AGENTS.md synced"
  else
    echo "!! ai-docs clone failed ($AI_DOCS_REPO); continuing with existing config"
  fi
else
  echo ">> ai-docs sync disabled (BB_SYNC_AI_DOCS=0)"
fi

# --- 3. retire stale ai-config symlinks -------------------------------------
# A previous setup symlinked these paths into ~/Dev/ai-config. That repo is
# retired; leaving the symlinks in place would shadow the synced files above
# and could resurrect deleted config. Break any remaining links.
mkdir -p "$HOME/.pi/agent"
for item in agents skills AGENTS.md agent-models.json; do
  target="$HOME/.pi/agent/$item"
  if [ -L "$target" ]; then
    echo ">> removing stale ai-config symlink: $item"
    rm -f "$target"
  fi
done

mkdir -p "$HOME/.bb" "$HOME/Dev"

echo ">> starting bb-app (web on :38886, Pi provider)"
exec "$@"
