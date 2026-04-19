#!/usr/bin/env bash
set -euo pipefail

# Start CLIProxyAPI (~/Documents/dev/CLIProxyAPI) using your existing Codex/ChatGPT
# subscription tokens from ~/.codex/auth.json, then print the env vars to use with Claude Code.
#
# Default Claude Code model: gpt-5.3-codex(high)
#
# Usage:
#   ./bin/proxy-start-codex.sh
#
# Optional overrides:
#   CLI_PROXY_DIR=~/Documents/dev/CLIProxyAPI PORT=8317 HOST=127.0.0.1 API_KEY=sk-dummy MODEL='gpt-5.3-codex(high)' ./bin/proxy-start-codex.sh

need_cmd() {
    command -v "$1" >/dev/null 2>&1 || {
        echo "Missing required command: $1" >&2
        exit 1
    }
}

need_cmd jq
need_cmd go

_SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "${_SCRIPT_DIR}/lib/proxy/preflight.sh"

CLI_PROXY_DIR="${CLI_PROXY_DIR:-$HOME/Documents/dev/CLIProxyAPI}"
HOST="${HOST:-127.0.0.1}"
PORT="${PORT:-8317}"
API_KEY="${API_KEY:-sk-dummy}"
MODEL="${MODEL:-gpt-5.3-codex(high)}"

if [[ ! -d "$CLI_PROXY_DIR" ]]; then
    echo "Not found: $CLI_PROXY_DIR" >&2
    echo "Clone it first:" >&2
    echo "  git clone https://github.com/router-for-me/CLIProxyAPI.git \"$CLI_PROXY_DIR\"" >&2
    exit 1
fi

CODEX_AUTH_JSON="$HOME/.codex/auth.json"
if [[ ! -f "$CODEX_AUTH_JSON" ]]; then
    echo "Not found: $CODEX_AUTH_JSON" >&2
    echo "Sign in with the Codex CLI first so this file exists, then re-run." >&2
    exit 1
fi

AUTH_DIR="$HOME/.cli-proxy-api"
AUTH_FILE="$AUTH_DIR/codex-import.json"
mkdir -p "$AUTH_DIR"

# Create an auth file that CLIProxyAPI loads from auth-dir on startup.
tmp="$(mktemp)"
jq '{type:"codex",access_token:.tokens.access_token,refresh_token:.tokens.refresh_token,id_token:.tokens.id_token,account_id:.tokens.account_id,last_refresh:.last_refresh,email:"chatgpt"}' \
    "$CODEX_AUTH_JSON" >"$tmp"
mv "$tmp" "$AUTH_FILE"
chmod 600 "$AUTH_FILE" || true

cd "$CLI_PROXY_DIR"

ensure_binary_current \
    "./cli-proxy-api" \
    "$CLI_PROXY_DIR" \
    "go build -o cli-proxy-api ./cmd/server"

CONFIG_FILE="./config.local.yaml"
cat >"$CONFIG_FILE" <<EOF
host: "$HOST"
port: $PORT
auth-dir: "~/.cli-proxy-api"
api-keys:
  - "$API_KEY"
remote-management:
  disable-control-panel: true
EOF

cat <<EOF

Proxy will start on: http://$HOST:$PORT

In a second terminal, run:
  export ANTHROPIC_BASE_URL=http://$HOST:$PORT
  export ANTHROPIC_AUTH_TOKEN=$API_KEY
  export ANTHROPIC_DEFAULT_OPUS_MODEL='$MODEL'
  export ANTHROPIC_DEFAULT_SONNET_MODEL='$MODEL'
  export ANTHROPIC_DEFAULT_HAIKU_MODEL='$MODEL'
  claude

EOF

exec ./cli-proxy-api --config "$CONFIG_FILE"
