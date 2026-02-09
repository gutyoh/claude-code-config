#!/usr/bin/env bash
set -euo pipefail

# Start antigravity-claude-proxy via npx.
# Called by bin/claude-proxy when --profile antigravity is used.
#
# Expects env vars from claude-proxy: HOST, PORT, API_KEY
# Antigravity uses PORT env var directly.

need_cmd() {
    command -v "$1" >/dev/null 2>&1 || {
        echo "Missing required command: $1" >&2
        exit 1
    }
}

need_cmd node
need_cmd npx

PORT="${PORT:-8081}" exec npx antigravity-claude-proxy@latest start
