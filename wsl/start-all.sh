#!/usr/bin/env bash
# Start the Paperclip stack in three tmux sessions: paperclip, paperclip-mcp, cc-connect.
# Idempotent: skips a session that is already running.
#
# Prereqs:
#   - tmux
#   - nvm + Node 20.x at $HOME/.nvm
#   - paperclip checked out at $HOME/work/paperclip (pnpm install done)
#   - paperclip-mcp checked out at $HOME/work/paperclip-mcp (venv set up)
#   - cc-connect on $PATH (npm i -g cc-connect, or local install in $HOME/.local/bin)
#   - $HOME/.cc-connect/config.toml present (see cc-connect.config.toml.example)
#   - $HOME/.local/bin/claude wrapper installed (see claude-wrapper)

set -u
export NVM_DIR="$HOME/.nvm"
[ -s "$NVM_DIR/nvm.sh" ] && . "$NVM_DIR/nvm.sh"
export PATH="$HOME/.local/bin:$PATH"

# Paperclip needs a stable JWT secret to sign agent run tokens.
# Generate once: openssl rand -hex 32
# Store in $HOME/.paperclip.env (gitignored) and source here, OR replace inline:
PAPERCLIP_AGENT_JWT_SECRET="${PAPERCLIP_AGENT_JWT_SECRET:-REPLACE_WITH_OPENSSL_RAND_HEX_32}"

start() {  # $1=session name  $2=command
  if tmux has-session -t "=$1" 2>/dev/null; then
    echo "[skip] tmux session '$1' already running"
  else
    tmux new-session -d -s "$1" "$2"
    echo "[start] tmux session '$1' launched"
  fi
}

start paperclip      "cd \$HOME/work/paperclip && export NVM_DIR=\$HOME/.nvm && . \$NVM_DIR/nvm.sh && export PAPERCLIP_AGENT_JWT_SECRET=$PAPERCLIP_AGENT_JWT_SECRET && pnpm dev 2>&1 | tee \$HOME/paperclip.log"
start paperclip-mcp  "cd \$HOME/work/paperclip-mcp && export NVM_DIR=\$HOME/.nvm && . \$NVM_DIR/nvm.sh && export PATH=\$HOME/.local/bin:\$PATH && source venv/bin/activate && paperclip-mcp 2>&1 | tee \$HOME/paperclip-mcp.log"

# cc-connect: CRITICAL — unset all proxy env vars before launch.
# Reason: cc-connect makes outbound calls to open.feishu.cn (China-hosted), and
# any HTTPS_PROXY pointing at Clash/FlClash will route those calls through an
# overseas node, where Feishu blocks the request with EOF.
# The `claude` binary it spawns gets proxy back via the wrapper at ~/.local/bin/claude.
# ANTHROPIC_MODEL pin avoids cc-connect picking opus when sonnet is sufficient.
start cc-connect     "export NVM_DIR=\$HOME/.nvm && . \$NVM_DIR/nvm.sh && export PATH=\$HOME/.local/bin:\$PATH && unset HTTP_PROXY HTTPS_PROXY http_proxy https_proxy ALL_PROXY all_proxy && export ANTHROPIC_MODEL=claude-sonnet-4-6 && cc-connect --config \$HOME/.cc-connect/config.toml 2>&1 | tee \$HOME/cc-connect.log"

echo
echo "Sessions:"; tmux ls 2>/dev/null || echo "  (none)"
echo "Attach with:  tmux attach -t paperclip   (Ctrl-b d to detach)"
echo "Logs:         ~/paperclip.log  ~/paperclip-mcp.log  ~/cc-connect.log"
