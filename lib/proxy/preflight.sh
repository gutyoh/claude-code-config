# preflight.sh -- Idempotent preflight checks for proxy launcher
# Path: lib/proxy/preflight.sh
# Sourced by bin/claude-proxy and bin/proxy-start-codex.sh — do not execute directly.
#
# Functions:
#   _binary_vcs_revision          Extract embedded VCS commit hash from a Go binary
#   _repo_head_revision           Get HEAD commit hash of a git repository
#   is_binary_current             Compare binary revision vs repo HEAD
#   ensure_binary_current         Rebuild Go binary if stale or missing (idempotent)
#   test_antigravity_session      Verify antigravity OAuth session via live API ping
#   open_url                      Open URL in default browser (cross-platform)
#   _timestamp_age_hours          Compute age of an ISO 8601 timestamp in hours
#   check_codex_token_freshness   Warn if Codex auth token is older than threshold

# --- Portable Python (PEP 394) ---
if command -v python3 &>/dev/null && python3 --version &>/dev/null; then
    _PY="python3"
else
    _PY="python"
fi

# --- Binary staleness (Go 1.18+ VCS metadata) ---

# _binary_vcs_revision <binary_path>
# Extracts the VCS revision embedded in a Go binary via `go version -m`.
# Prints the 40-char commit hash to stdout, or empty string if not found.
# Returns 0 on success, 1 if binary not found or not executable.
_binary_vcs_revision() {
    local bin="$1"
    [[ -x "$bin" ]] || return 1
    go version -m "$bin" 2>/dev/null | sed -n 's/.*vcs\.revision=//p'
}

# _repo_head_revision <repo_dir>
# Gets the HEAD commit hash of a git repository.
# Returns 0 on success, 1 if not a git repo or git not available.
_repo_head_revision() {
    local repo_dir="$1"
    git -C "$repo_dir" rev-parse HEAD 2>/dev/null
}

# is_binary_current <binary_path> <repo_dir>
# Checks if a Go binary's embedded VCS revision matches the repository HEAD.
# Returns: 0=current, 1=missing, 2=stale (revision mismatch), 3=unable to determine.
is_binary_current() {
    local bin="$1"
    local repo_dir="$2"

    if [[ ! -x "$bin" ]]; then
        echo "Binary not found: $bin" >&2
        return 1
    fi

    local binary_rev
    binary_rev=$(_binary_vcs_revision "$bin")
    if [[ -z "$binary_rev" ]]; then
        echo "No VCS metadata in binary (built outside git?)" >&2
        return 3
    fi

    local head_rev
    head_rev=$(_repo_head_revision "$repo_dir")
    if [[ -z "$head_rev" ]]; then
        echo "Cannot determine HEAD for: $repo_dir" >&2
        return 3
    fi

    if [[ "$binary_rev" == "$head_rev" ]]; then
        return 0
    fi

    echo "Binary stale: built from ${binary_rev:0:12}, HEAD is ${head_rev:0:12}" >&2
    return 2
}

# ensure_binary_current <binary_path> <repo_dir> <build_cmd>
# Ensures the Go binary matches the repository HEAD. Rebuilds if stale or missing.
# Idempotent: if binary is current, does nothing.
# Returns 0 on success, 1 on build failure.
ensure_binary_current() {
    local bin="$1"
    local repo_dir="$2"
    local build_cmd="$3"

    local rc=0
    is_binary_current "$bin" "$repo_dir" || rc=$?

    case $rc in
        0) return 0 ;;
        1) echo "Building $bin (first build)..." >&2 ;;
        2) echo "Rebuilding $bin (source updated)..." >&2 ;;
        3) echo "Rebuilding $bin (cannot verify currency)..." >&2 ;;
    esac

    # shellcheck disable=SC2086
    (cd "$repo_dir" && eval $build_cmd) || {
        echo "Build failed: $build_cmd" >&2
        return 1
    }
}

# --- Token freshness ---

# _timestamp_age_hours <iso8601_timestamp>
# Returns the age of an ISO 8601 timestamp in whole hours.
# Uses python3 for reliable cross-platform parsing (fractional seconds, Z suffix).
# Returns 0 on success, 1 if parsing fails.
_timestamp_age_hours() {
    local ts="$1"
    [[ -n "$ts" ]] || return 1

    "${_PY}" -c "
from datetime import datetime, timezone
try:
    dt = datetime.fromisoformat('$ts'.replace('Z', '+00:00'))
    now = datetime.now(timezone.utc)
    print(int((now - dt).total_seconds() / 3600))
except Exception:
    exit(1)
" 2>/dev/null
}

# --- Antigravity session verification ---

# test_antigravity_session <url> <api_key> <model>
# Sends a minimal API request to verify the antigravity session is valid.
# Returns 0 if session is valid (any non-auth HTTP code), 1 if expired (401/403/405).
test_antigravity_session() {
    local _url="$1"
    local _key="$2"
    local _model="$3"

    local http_code
    http_code=$(curl -s -o /dev/null -w '%{http_code}' --max-time 10 \
        -X POST "${_url}/v1/messages" \
        -H "Content-Type: application/json" \
        -H "x-api-key: ${_key}" \
        -H "anthropic-version: 2023-06-01" \
        -d '{"model":"'"${_model}"'","max_tokens":1,"messages":[{"role":"user","content":"ping"}]}')
    case "${http_code}" in
        405 | 401 | 403) return 1 ;;
        *) return 0 ;;
    esac
}

# open_url <url>
# Opens a URL in the default browser. Falls back to printing the URL.
# macOS: open, Linux: xdg-open, other: prints to stderr.
open_url() {
    local url="$1"
    if command -v open >/dev/null 2>&1; then
        open "$url"
    elif command -v xdg-open >/dev/null 2>&1; then
        xdg-open "$url"
    else
        echo "  Open in your browser: $url" >&2
    fi
}

# --- Dynamic model discovery ---

# fetch_proxy_models <proxy_url>
# Queries the proxy's /v1/models endpoint for live model data.
# Prints sorted model IDs (one per line) to stdout.
# Returns 0 on success, 1 if unreachable, invalid JSON, empty list, or jq missing.
fetch_proxy_models() {
    local proxy_url="$1"
    command -v jq >/dev/null 2>&1 || return 1

    local response
    response=$(curl -sf --max-time 1 "${proxy_url}/v1/models" 2>/dev/null) || return 1

    local models
    models=$(echo "${response}" | jq -r '.data[]?.id // empty' 2>/dev/null) || return 1
    [[ -z "${models}" ]] && return 1

    echo "${models}" | sort
}

# --- Token freshness ---

# check_codex_token_freshness <auth_json_path> [max_age_hours]
# Warns if the Codex auth token is older than the threshold (default 48h).
# Does NOT fail — CLIProxyAPI may auto-refresh using the refresh_token.
# Outputs token age in hours to stdout.
# Returns: 0=fresh, 1=stale, 2=auth file missing, 3=cannot parse.
check_codex_token_freshness() {
    local auth_json="$1"
    local max_age_hours="${2:-48}"

    if [[ ! -f "$auth_json" ]]; then
        echo "Auth file not found: $auth_json" >&2
        return 2
    fi

    local last_refresh
    last_refresh=$(jq -r '.last_refresh // empty' "$auth_json" 2>/dev/null)
    if [[ -z "$last_refresh" ]]; then
        echo "No last_refresh timestamp in: $auth_json" >&2
        return 3
    fi

    local age_hours
    age_hours=$(_timestamp_age_hours "$last_refresh") || {
        echo "Cannot parse timestamp: $last_refresh" >&2
        return 3
    }

    echo "$age_hours"

    if [[ "$age_hours" -gt "$max_age_hours" ]]; then
        echo "Warning: Codex token is ${age_hours}h old (threshold: ${max_age_hours}h)." >&2
        echo "  CLIProxyAPI will attempt auto-refresh, but if you see HTTP 500 errors," >&2
        echo "  re-authenticate with:  codex" >&2
        return 1
    fi

    return 0
}
