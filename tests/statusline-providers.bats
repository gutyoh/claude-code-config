#!/usr/bin/env bats
# statusline-providers.bats
# Path: tests/statusline-providers.bats
#
# bats-core tests for providers.sh: which plan a model's usage comes from, the
# ChatGPT and Muse readers, and how their windows reach the statusline.
#
# curl is stubbed: it records its arguments and stdin, and answers with
# $BATS_TEST_TMPDIR/body.json, so no test touches the network or a real login.
#
# Run: bats tests/statusline-providers.bats
#      just test

MODULES_DIR="$BATS_TEST_DIRNAME/../.claude/scripts/lib/statusline"
STATUSLINE="$BATS_TEST_DIRNAME/../.claude/scripts/statusline.sh"

setup() {
    source "$BATS_TEST_DIRNAME/helpers.bash"
    isolate_home
    stub_bin ccusage 'echo "{\"blocks\":[]}"'
    stub_curl

    _TMP_DIR="$BATS_TEST_TMPDIR/tmp"
    mkdir -p "$_TMP_DIR"
    CACHE_FILE="$_TMP_DIR/api-cache"
    LOCK_DIR="$_TMP_DIR/api-lock"
    BACKOFF_FILE="$_TMP_DIR/api-backoff"
    CACHE_TTL=180
    LOCK_MAX_AGE_S=30
    BACKOFF_INITIAL_S=30
    BACKOFF_MAX_S=300
    PLATFORM="$(detect_test_platform)"

    debug() { :; }
    debug_var() { :; }
    collect_service_status() { :; }
    DATA_CC_STATUS=""

    source "$MODULES_DIR/api.sh"
    source "$MODULES_DIR/cache.sh"
    source "$MODULES_DIR/providers.sh"
    source "$MODULES_DIR/utils.sh"
    source "$MODULES_DIR/data.sh"

    NOW=$(date +%s)
    unset CODEX_HOME MUSE_AUTH_PATH STATUSLINE_OPENAI_AUTH STATUSLINE_MUSE_AUTH STATUSLINE_HTTPS_PROXY
}

# curl stub: records argv and stdin; answers body.json, or fails like -f on
# an HTTP error when curl.fail exists.
stub_curl() {
    local dir="$BATS_TEST_TMPDIR"
    stub_bin curl \
        "cat >'$dir/curl.stdin'" \
        "printf '%s\n' \"\$@\" >'$dir/curl.argv'" \
        "[[ -f '$dir/curl.fail' ]] && exit 22" \
        "cat '$dir/body.json'"
}

set_file_mtime() {
    "${_PY}" -c "import os,sys; os.utime(sys.argv[1], (int(sys.argv[2]), int(sys.argv[2])))" "$1" "$2"
}

body() { printf '%s' "$1" >"$BATS_TEST_TMPDIR/body.json"; }

openai_login() {
    mkdir -p "$HOME/.codex"
    printf '{"tokens":{"access_token":"tok-openai-secret","account_id":"acct-1"}}' >"$HOME/.codex/auth.json"
}

muse_login() {
    mkdir -p "$XDG_CONFIG_HOME/muse"
    printf '{"providers":{"meta":{"accessToken":"dca:muse-secret","mechanism":"oauth"}}}' >"$XDG_CONFIG_HOME/muse/auth.json"
}

field() { printf '%s' "$1" | cut -f"$2"; }

# =========================================================================
# usage_provider
# =========================================================================

@test "usage_provider: Claude ids, aliases and no id at all are claude" {
    [[ "$(usage_provider claude-opus-5-5)" == "claude" ]]
    [[ "$(usage_provider us.anthropic.claude-sonnet-5-5)" == "claude" ]]
    [[ "$(usage_provider "")" == "claude" ]]
    [[ "$(usage_provider opus)" == "claude" ]]
    [[ "$(usage_provider sonnet[1m])" == "claude" ]]
    [[ "$(usage_provider opusplan)" == "claude" ]]
    [[ "$(usage_provider default)" == "claude" ]]
}

@test "usage_provider: GPT and Codex models are openai" {
    [[ "$(usage_provider gpt-6.1-sol)" == "openai" ]]
    [[ "$(usage_provider gpt-6.1-sol-fast)" == "openai" ]]
    [[ "$(usage_provider gpt-6-astra)" == "openai" ]]
    [[ "$(usage_provider o4-mini)" == "openai" ]]
    [[ "$(usage_provider codex-mini)" == "openai" ]]
}

@test "usage_provider: Muse models are muse, unknown models none" {
    [[ "$(usage_provider muse-spark)" == "muse" ]]
    [[ "$(usage_provider kimi-k3)" == "none" ]]
}

# =========================================================================
# ChatGPT reader
# =========================================================================

@test "openai: weekly-only plan (weekly sent as primary) has no 5-hour window" {
    openai_login
    body '{"rate_limit":{"primary_window":{"used_percent":8,"limit_window_seconds":604800,"reset_at":1792326758},"secondary_window":null}}'
    run fetch_openai_usage
    [ "$status" -eq 0 ]
    [[ "$(field "$output" 1)" == "" ]]
    [[ "$(field "$output" 2)" == "" ]]
    [[ "$(field "$output" 3)" == "8" ]]
    [[ "$(field "$output" 4)" == "1792326758" ]]
    [[ "$(field "$output" 5)" =~ ^[0-9]+$ ]]
    [[ "$(field "$output" 6)" == "$(field "$output" 5)" ]]
}

@test "openai: 5-hour and weekly windows are labeled by length, not slot" {
    openai_login
    body '{"rate_limit":{"primary_window":{"used_percent":61,"limit_window_seconds":604800,"reset_at":200},"secondary_window":{"used_percent":42,"limit_window_seconds":18000,"reset_at":100}}}'
    run fetch_openai_usage
    [ "$status" -eq 0 ]
    [[ "$(field "$output" 1)" == "42" ]]
    [[ "$(field "$output" 2)" == "100" ]]
    [[ "$(field "$output" 3)" == "61" ]]
    [[ "$(field "$output" 4)" == "200" ]]
}

@test "openai: no windows at all is a failure, so the last reading is kept" {
    openai_login
    body '{"rate_limit":null}'
    run fetch_openai_usage
    [ "$status" -ne 0 ]
}

@test "openai: HTTP error is a failure" {
    openai_login
    touch "$BATS_TEST_TMPDIR/curl.fail"
    run fetch_openai_usage
    [ "$status" -ne 0 ]
}

@test "openai: no login is a failure and calls nothing" {
    run fetch_openai_usage
    [ "$status" -ne 0 ]
    [ ! -f "$BATS_TEST_TMPDIR/curl.argv" ]
}

@test "openai: the token goes to curl on stdin, never in its arguments" {
    openai_login
    body '{"rate_limit":{"primary_window":{"used_percent":8,"limit_window_seconds":604800,"reset_at":1}}}'
    run fetch_openai_usage
    [ "$status" -eq 0 ]
    ! grep -q "tok-openai-secret" "$BATS_TEST_TMPDIR/curl.argv"
    grep -q 'header = "Authorization: Bearer tok-openai-secret"' "$BATS_TEST_TMPDIR/curl.stdin"
    grep -q "ChatGPT-Account-Id: acct-1" "$BATS_TEST_TMPDIR/curl.argv"
    grep -q "https://chatgpt.com/backend-api/wham/usage" "$BATS_TEST_TMPDIR/curl.argv"
}

@test "STATUSLINE_HTTPS_PROXY set but empty sends the requests direct" {
    openai_login
    export STATUSLINE_HTTPS_PROXY=""
    body '{"rate_limit":{"primary_window":{"used_percent":8,"limit_window_seconds":604800,"reset_at":1}}}'
    run fetch_openai_usage
    [ "$status" -eq 0 ]
    grep -qx 'proxy = ""' "$BATS_TEST_TMPDIR/curl.stdin"
}

@test "STATUSLINE_HTTPS_PROXY names the statusline's own proxy" {
    muse_login
    export STATUSLINE_HTTPS_PROXY="http://proxy.example:3128"
    body '{"is_subs_active":true}'
    run fetch_muse_usage
    [ "$status" -eq 0 ]
    grep -qx 'proxy = "http://proxy.example:3128"' "$BATS_TEST_TMPDIR/curl.stdin"
}

@test "STATUSLINE_HTTPS_PROXY unset leaves the session's proxy alone" {
    openai_login
    unset STATUSLINE_HTTPS_PROXY
    body '{"rate_limit":{"primary_window":{"used_percent":8,"limit_window_seconds":604800,"reset_at":1}}}'
    run fetch_openai_usage
    [ "$status" -eq 0 ]
    ! grep -q '^proxy' "$BATS_TEST_TMPDIR/curl.stdin"
}

@test "Claude's OAuth request honours STATUSLINE_HTTPS_PROXY too" {
    export STATUSLINE_HTTPS_PROXY=""
    body '{}'
    API_URL="https://api.anthropic.com/api/oauth/usage"; CURL_TIMEOUT=5; API_BETA_HEADER="oauth-2025-04-20"
    run fetch_api_usage "tok-claude"
    grep -qx 'proxy = ""' "$BATS_TEST_TMPDIR/curl.stdin"
    grep -q 'Bearer tok-claude' "$BATS_TEST_TMPDIR/curl.stdin"
    ! grep -q "tok-claude" "$BATS_TEST_TMPDIR/curl.argv"
}

@test "openai: CODEX_HOME names the login" {
    mkdir -p "$BATS_TEST_TMPDIR/codex-home"
    printf '{"tokens":{"access_token":"tok-codex-home"}}' >"$BATS_TEST_TMPDIR/codex-home/auth.json"
    export CODEX_HOME="$BATS_TEST_TMPDIR/codex-home"
    body '{"rate_limit":{"primary_window":{"used_percent":3,"limit_window_seconds":18000,"reset_at":1}}}'
    run fetch_openai_usage
    [ "$status" -eq 0 ]
    grep -q "tok-codex-home" "$BATS_TEST_TMPDIR/curl.stdin"
}

@test "openai: STATUSLINE_OPENAI_AUTH wins over CODEX_HOME" {
    openai_login
    export CODEX_HOME="$HOME/.codex"
    mkdir -p "$BATS_TEST_TMPDIR/router/chatgpt"
    printf '{"tokens":{"access_token":"tok-router"}}' >"$BATS_TEST_TMPDIR/router/chatgpt/auth.json"
    export STATUSLINE_OPENAI_AUTH="$BATS_TEST_TMPDIR/router/chatgpt/auth.json"
    body '{"rate_limit":{"primary_window":{"used_percent":3,"limit_window_seconds":18000,"reset_at":1}}}'
    run fetch_openai_usage
    [ "$status" -eq 0 ]
    grep -q "tok-router" "$BATS_TEST_TMPDIR/curl.stdin"
}

# =========================================================================
# Muse reader
# =========================================================================

@test "muse: active windows are read from subs_usage" {
    muse_login
    body '{"is_subs_active":true,"subs_usage":{"window":{"used_percent":6,"window_duration_mins":300,"resets_at":'"$((NOW + 3600))"'},"weekly":{"used_percent":17,"resets_at":'"$((NOW + 86400))"'}}}'
    run fetch_muse_usage
    [ "$status" -eq 0 ]
    [[ "$(field "$output" 1)" == "6" ]]
    [[ "$(field "$output" 2)" == "$((NOW + 3600))" ]]
    [[ "$(field "$output" 3)" == "17" ]]
    [[ "$(field "$output" 4)" == "$((NOW + 86400))" ]]
}

@test "muse: a 5-hour window past its reset reads 0" {
    muse_login
    body '{"is_subs_active":true,"subs_usage":{"window":{"used_percent":90,"resets_at":'"$((NOW - 10))"'},"weekly":{"used_percent":17,"resets_at":'"$((NOW + 86400))"'}}}'
    run fetch_muse_usage
    [ "$status" -eq 0 ]
    [[ "$(field "$output" 1)" == "0" ]]
    [[ "$(field "$output" 2)" == "" ]]
}

@test "collect_data: an idle Muse window shows 0 with no countdown" {
    muse_login
    body '{"is_subs_active":true}'
    collect_data '{"model":{"id":"muse-spark-1.3"}}'
    [[ "$DATA_SESSION_PCT" == "0" ]]
    [[ "$DATA_TIME_LEFT" == "" ]]
    [[ "$DATA_WEEKLY_PCT" == "" ]]
}

@test "muse: idle window is 0 and the weekly keeps its last reading" {
    muse_login
    printf '6\t%s\t17\t%s\t%s\t%s' "$((NOW - 60))" "$((NOW + 86400))" "$((NOW - 600))" "$((NOW - 7200))" >"$BATS_TEST_TMPDIR/prev"
    CACHE_FILE="$BATS_TEST_TMPDIR/prev"
    body '{"is_subs_active":true}'
    run fetch_muse_usage
    [ "$status" -eq 0 ]
    [[ "$(field "$output" 1)" == "0" ]]
    [[ "$(field "$output" 3)" == "17" ]]
    [[ "$(field "$output" 4)" == "$((NOW + 86400))" ]]
    # Fetched now, but the weekly reading keeps the time Meta last reported it
    [[ "$(field "$output" 5)" -ge "$NOW" ]]
    [[ "$(field "$output" 6)" == "$((NOW - 7200))" ]]
}

@test "muse: idle carry from an older five-field reading uses its fetch time" {
    muse_login
    printf '6\t1\t17\t%s\t%s' "$((NOW + 86400))" "$((NOW - 900))" >"$BATS_TEST_TMPDIR/prev"
    CACHE_FILE="$BATS_TEST_TMPDIR/prev"
    body '{"is_subs_active":true}'
    run fetch_muse_usage
    [ "$status" -eq 0 ]
    [[ "$(field "$output" 3)" == "17" ]]
    [[ "$(field "$output" 6)" == "$((NOW - 900))" ]]
}

@test "muse: an active reading is seen now" {
    muse_login
    body '{"is_subs_active":true,"subs_usage":{"window":{"used_percent":6,"resets_at":'"$((NOW + 3600))"'},"weekly":{"used_percent":17,"resets_at":'"$((NOW + 86400))"'}}}'
    run fetch_muse_usage
    [ "$status" -eq 0 ]
    [[ "$(field "$output" 6)" -ge "$NOW" ]]
    [[ "$(field "$output" 6)" == "$(field "$output" 5)" ]]
}

@test "muse: idle with an expired last weekly shows no weekly" {
    muse_login
    printf '6\t1\t17\t%s\t1' "$((NOW - 5))" >"$BATS_TEST_TMPDIR/prev"
    CACHE_FILE="$BATS_TEST_TMPDIR/prev"
    body '{"is_subs_active":true}'
    run fetch_muse_usage
    [ "$status" -eq 0 ]
    [[ "$(field "$output" 1)" == "0" ]]
    [[ "$(field "$output" 3)" == "" ]]
}

@test "muse: no active subscription is a failure" {
    muse_login
    body '{"is_subs_active":false}'
    run fetch_muse_usage
    [ "$status" -ne 0 ]
}

@test "muse: a login that is not a device login is refused before any call" {
    mkdir -p "$XDG_CONFIG_HOME/muse"
    printf '{"providers":{"meta":{"accessToken":"LLM|not-a-device-token"}}}' >"$XDG_CONFIG_HOME/muse/auth.json"
    run fetch_muse_usage
    [ "$status" -ne 0 ]
    [ ! -f "$BATS_TEST_TMPDIR/curl.argv" ]
}

@test "muse: a router's login (dca_token) found through a glob" {
    mkdir -p "$BATS_TEST_TMPDIR/router/muse/auth"
    printf '{"dca_token":"dca:router-secret","access_token":"LLM|x"}' >"$BATS_TEST_TMPDIR/router/muse/auth/meta-a.json"
    export STATUSLINE_MUSE_AUTH="$BATS_TEST_TMPDIR/router/muse/auth/meta-*.json"
    body '{"is_subs_active":true}'
    run fetch_muse_usage
    [ "$status" -eq 0 ]
    grep -q "dca:router-secret" "$BATS_TEST_TMPDIR/curl.stdin"
    ! grep -q "router-secret" "$BATS_TEST_TMPDIR/curl.argv"
    grep -q -- "-X" "$BATS_TEST_TMPDIR/curl.argv"
    grep -q "x-api-version: 1.0.0" "$BATS_TEST_TMPDIR/curl.argv"
}

@test "login lookup works without compgen, which some bash builds lack" {
    mkdir -p "$BATS_TEST_TMPDIR/router/muse/auth"
    printf '{"dca_token":"dca:x"}' >"$BATS_TEST_TMPDIR/router/muse/auth/meta-b.json"
    enable -n compgen
    run _first_file "$BATS_TEST_TMPDIR/router/muse/auth/meta-*.json"
    enable compgen
    [ "$status" -eq 0 ]
    [[ "$output" == "$BATS_TEST_TMPDIR/router/muse/auth/meta-b.json" ]]
}

@test "login lookup keeps a path with spaces whole" {
    mkdir -p "$BATS_TEST_TMPDIR/Application Support/codex"
    printf '{}' >"$BATS_TEST_TMPDIR/Application Support/codex/auth.json"
    run _first_file "$BATS_TEST_TMPDIR/Application Support/codex/auth.json"
    [ "$status" -eq 0 ]
    [[ "$output" == "$BATS_TEST_TMPDIR/Application Support/codex/auth.json" ]]
    run _first_file "$BATS_TEST_TMPDIR/Application Support/*/auth.json"
    [[ "$output" == "$BATS_TEST_TMPDIR/Application Support/codex/auth.json" ]]
}

@test "login lookup: a missing file or an unmatched glob finds nothing" {
    run _first_file "$BATS_TEST_TMPDIR/nope/auth.json"
    [ "$status" -ne 0 ]
    run _first_file "$BATS_TEST_TMPDIR/nope/meta-*.json"
    [ "$status" -ne 0 ]
    [ -z "$output" ]
}

@test "login lookup leaves the caller's nullglob as it was" {
    shopt -u nullglob
    _first_file "$BATS_TEST_TMPDIR/nope/*" || true
    ! shopt -q nullglob
    shopt -s nullglob
    _first_file "$BATS_TEST_TMPDIR/nope/*" || true
    shopt -q nullglob
    shopt -u nullglob
}

# =========================================================================
# Cache and statusline data
# =========================================================================

@test "provider cache: fresh reading served without a call" {
    openai_login
    local key="openai-$(printf '%s' "$HOME/.codex/auth.json" | cksum | cut -d' ' -f1)"
    mkdir -p "$(usage_state_dir)"
    printf '\t\t8\t1\t%s' "$NOW" >"$(usage_state_dir)/usage-$key"
    run get_provider_usage openai
    [ "$status" -eq 0 ]
    [[ "$(field "$output" 3)" == "8" ]]
    [ ! -f "$BATS_TEST_TMPDIR/curl.argv" ]
}

@test "provider cache: two logins never share a reading" {
    openai_login
    body '{"rate_limit":{"primary_window":{"used_percent":8,"limit_window_seconds":604800,"reset_at":1}}}'
    get_provider_usage openai >/dev/null
    mkdir -p "$BATS_TEST_TMPDIR/other"
    printf '{"tokens":{"access_token":"tok-2"}}' >"$BATS_TEST_TMPDIR/other/auth.json"
    export STATUSLINE_OPENAI_AUTH="$BATS_TEST_TMPDIR/other/auth.json"
    body '{"rate_limit":{"primary_window":{"used_percent":55,"limit_window_seconds":604800,"reset_at":1}}}'
    run get_provider_usage openai
    [[ "$(field "$output" 3)" == "55" ]]
    [ "$(ls "$(usage_state_dir)"/usage-openai-* | wc -l)" -eq 2 ]
}

@test "provider cache: an error keeps serving the last reading" {
    openai_login
    local key="openai-$(printf '%s' "$HOME/.codex/auth.json" | cksum | cut -d' ' -f1)"
    mkdir -p "$(usage_state_dir)"
    printf '\t\t8\t1\t%s' "$((NOW - 1000))" >"$(usage_state_dir)/usage-$key"
    set_file_mtime "$(usage_state_dir)/usage-$key" "$((NOW - 1000))"
    touch "$BATS_TEST_TMPDIR/curl.fail"
    run get_provider_usage openai
    [ "$status" -eq 0 ]
    [[ "$(field "$output" 3)" == "8" ]]
    [ -f "$_TMP_DIR/usage-$key.backoff" ]
}

@test "collect_data: a GPT session shows the ChatGPT plan and never asks Claude" {
    openai_login
    body '{"rate_limit":{"primary_window":{"used_percent":8,"limit_window_seconds":604800,"reset_at":'"$((NOW + 86400))"'}}}'
    eval 'get_api_session_data() { touch "$BATS_TEST_TMPDIR/claude-called"; return 1; }'
    collect_data '{"model":{"id":"gpt-6.1-sol-fast","display_name":"gpt-6.1-sol-fast"}}'
    [[ "$DATA_USAGE_PROVIDER" == "openai" ]]
    [[ "$DATA_SESSION_PCT" == "" ]]
    [[ "$DATA_TIME_LEFT" == "" ]]
    [[ "$DATA_WEEKLY_PCT" == "8" ]]
    [ ! -f "$BATS_TEST_TMPDIR/claude-called" ]
}

@test "collect_data: an old provider reading is marked approximate" {
    openai_login
    local key="openai-$(printf '%s' "$HOME/.codex/auth.json" | cksum | cut -d' ' -f1)"
    mkdir -p "$(usage_state_dir)"
    printf '3\t1\t8\t1\t%s' "$((NOW - 2000))" >"$(usage_state_dir)/usage-$key"
    touch "$BATS_TEST_TMPDIR/curl.fail"
    DATA_SESSION_PCT_STALE=0
    DATA_WEEKLY_PCT_STALE=0
    collect_data '{"model":{"id":"gpt-6-astra"}}'
    [[ "$DATA_WEEKLY_PCT" == "8" ]]
    [[ "$DATA_SESSION_PCT_STALE" == "1" ]]
    [[ "$DATA_WEEKLY_PCT_STALE" == "1" ]]
}

@test "provider readings live in XDG_STATE_HOME, not the temp directory" {
    export XDG_STATE_HOME="$BATS_TEST_TMPDIR/state"
    openai_login
    body '{"rate_limit":{"primary_window":{"used_percent":8,"limit_window_seconds":604800,"reset_at":1}}}'
    get_provider_usage openai >/dev/null
    ls "$XDG_STATE_HOME"/claude-code/statusline/usage-openai-* >/dev/null
    ! ls "$_TMP_DIR"/usage-openai-* 2>/dev/null | grep -qv '\.\(lock\|backoff\)$'
}

@test "a carried weekly reading survives a wiped temp directory" {
    muse_login
    body '{"is_subs_active":true,"subs_usage":{"window":{"used_percent":6,"resets_at":'"$((NOW + 3600))"'},"weekly":{"used_percent":17,"resets_at":'"$((NOW + 86400))"'}}}'
    get_provider_usage muse >/dev/null
    # A reboot: the temp directory is gone and the 5-hour window is idle
    rm -rf "$_TMP_DIR"
    mkdir -p "$_TMP_DIR"
    set_file_mtime "$(ls "$(usage_state_dir)"/usage-muse-*)" "$((NOW - 1000))"
    body '{"is_subs_active":true}'
    collect_data '{"model":{"id":"muse-spark-1.3"}}'
    [[ "$DATA_SESSION_PCT" == "0" ]]
    [[ "$DATA_WEEKLY_PCT" == "17" ]]
}

@test "collect_data: an old weekly reading is approximate while a fresh session is not" {
    muse_login
    local key="muse-$(printf '%s' "$XDG_CONFIG_HOME/muse/auth.json" | cksum | cut -d' ' -f1)"
    mkdir -p "$(usage_state_dir)"
    printf '0\t\t17\t%s\t%s\t%s' "$((NOW + 86400))" "$NOW" "$((NOW - 7200))" >"$(usage_state_dir)/usage-$key"
    DATA_SESSION_PCT_STALE=0
    DATA_WEEKLY_PCT_STALE=0
    collect_data '{"model":{"id":"muse-spark-1.3"}}'
    [[ "$DATA_WEEKLY_PCT" == "17" ]]
    [[ "$DATA_SESSION_PCT_STALE" == "0" ]]
    [[ "$DATA_WEEKLY_PCT_STALE" == "1" ]]
}

@test "statusline: an old carried weekly renders with ~" {
    muse_login
    local key="muse-$(printf '%s' "$XDG_CONFIG_HOME/muse/auth.json" | cksum | cut -d' ' -f1)"
    mkdir -p "$(usage_state_dir)" "$HOME/.claude"
    printf '0\t\t17\t%s\t%s\t%s' "$((NOW + 86400))" "$NOW" "$((NOW - 7200))" >"$(usage_state_dir)/usage-$key"
    printf 'components=model,usage,weekly\ntheme=none\n' >"$HOME/.claude/statusline.conf"
    run env TMPDIR="$BATS_TEST_TMPDIR" COLUMNS=200 bash "$STATUSLINE" \
        <<<'{"model":{"id":"muse-spark-1.3","display_name":"muse-spark-1.3"},"session_id":"s4"}'
    [ "$status" -eq 0 ]
    [[ "$output" == "muse-spark-1.3 | 0%/~17%" ]]
}

@test "collect_data: a model with no reader shows --, not Claude's usage" {
    eval 'get_api_session_data() { touch "$BATS_TEST_TMPDIR/claude-called"; return 1; }'
    DATA_SESSION_PCT="--"
    DATA_WEEKLY_PCT="--"
    collect_data '{"model":{"id":"kimi-k3"}}'
    [[ "$DATA_SESSION_PCT" == "--" ]]
    [[ "$DATA_WEEKLY_PCT" == "--" ]]
    [ ! -f "$BATS_TEST_TMPDIR/claude-called" ]
}

# =========================================================================
# End to end
# =========================================================================

@test "statusline: a weekly-only GPT plan renders the weekly and hides the rest" {
    openai_login
    body '{"rate_limit":{"primary_window":{"used_percent":8,"limit_window_seconds":604800,"reset_at":'"$((NOW + 86400))"'}}}'
    printf 'components=model,usage,weekly,reset\ntheme=none\n' >"$HOME/.claude/statusline.conf" 2>/dev/null \
        || { mkdir -p "$HOME/.claude" && printf 'components=model,usage,weekly,reset\ntheme=none\n' >"$HOME/.claude/statusline.conf"; }
    run env TMPDIR="$BATS_TEST_TMPDIR" COLUMNS=200 bash "$STATUSLINE" \
        <<<'{"model":{"id":"gpt-6.1-sol-fast","display_name":"gpt-6.1-sol-fast"},"session_id":"s1"}'
    [ "$status" -eq 0 ]
    [[ "$output" == "gpt-6.1-sol-fast | 8%" ]]
}

@test "statusline: a Muse session renders both windows" {
    muse_login
    body '{"is_subs_active":true,"subs_usage":{"window":{"used_percent":6,"resets_at":'"$((NOW + 3600))"'},"weekly":{"used_percent":17,"resets_at":'"$((NOW + 86400))"'}}}'
    mkdir -p "$HOME/.claude"
    printf 'components=model,usage,weekly\ntheme=none\n' >"$HOME/.claude/statusline.conf"
    run env TMPDIR="$BATS_TEST_TMPDIR" COLUMNS=200 bash "$STATUSLINE" \
        <<<'{"model":{"id":"muse-spark","display_name":"muse-spark"},"session_id":"s2"}'
    [ "$status" -eq 0 ]
    [[ "$output" == "muse-spark | 6%/17%" ]]
}

@test "statusline: a Pro or Max Claude session renders stdin rate_limits" {
    mkdir -p "$HOME/.claude"
    printf 'components=model,usage,weekly\ntheme=none\n' >"$HOME/.claude/statusline.conf"
    run env TMPDIR="$BATS_TEST_TMPDIR" COLUMNS=200 bash "$STATUSLINE" \
        <<<'{"model":{"id":"claude-opus-5-5","display_name":"Opus 5.5"},"session_id":"s3","rate_limits":{"five_hour":{"used_percentage":12,"resets_at":'"$((NOW + 3600))"'},"seven_day":{"used_percentage":58,"resets_at":'"$((NOW + 86400))"'}}}'
    [ "$status" -eq 0 ]
    [[ "$output" == "opus-5.5 | 12%/58%" ]]
    [ ! -f "$BATS_TEST_TMPDIR/curl.argv" ]
}

# =========================================================================
# Claude: one reading per account, shared by every session
# =========================================================================

claude_json() { # five_pct five_reset week_pct week_reset
    printf '{"model":{"id":"claude-opus-5-5","display_name":"Opus 5.5"},"rate_limits":{"five_hour":{"used_percentage":%s,"resets_at":%s},"seven_day":{"used_percentage":%s,"resets_at":%s}}}' "$@"
}

render_claude() {
    DATA_SESSION_PCT="--"
    DATA_WEEKLY_PCT="--"
    DATA_SESSION_PCT_STALE=0
    DATA_WEEKLY_PCT_STALE=0
    collect_data "$1"
}

@test "account: a quiet session shows what another session saw since" {
    eval 'get_api_session_data() { return 1; }'
    local r5=$((NOW + 3600)) r7=$((NOW + 86400))
    render_claude "$(claude_json 5 $r5 61 $r7)"   # the busy session
    render_claude "$(claude_json 4 $r5 60 $r7)"   # the quiet one, behind
    [[ "$DATA_SESSION_PCT" == "5" ]]
    [[ "$DATA_WEEKLY_PCT" == "61" ]]
}

@test "account: an older reading never replaces a newer one" {
    eval 'get_api_session_data() { return 1; }'
    local r5=$((NOW + 3600)) r7=$((NOW + 86400))
    render_claude "$(claude_json 9 $r5 70 $r7)"
    render_claude "$(claude_json 3 $r5 65 $r7)"
    render_claude "$(claude_json 3 $r5 65 $r7)"
    IFS=$'\t' read -r five week <"$(claude_account_file)"
    [[ "${five%%|*}" == "9" ]]
    [[ "${week%%|*}" == "70" ]]
}

@test "account: a new window replaces a higher reading of the old one" {
    eval 'get_api_session_data() { return 1; }'
    render_claude "$(claude_json 90 $((NOW - 60)) 61 $((NOW + 86400)))"
    render_claude "$(claude_json 2 $((NOW + 18000)) 61 $((NOW + 86400)))"
    [[ "$DATA_SESSION_PCT" == "2" ]]
}

@test "account: the shared OAuth reading counts when it is ahead of stdin" {
    local iso5 iso7
    iso5=$(date -u -d "@$((NOW + 3600))" +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || date -u -r "$((NOW + 3600))" +%Y-%m-%dT%H:%M:%SZ)
    iso7=$(date -u -d "@$((NOW + 86400))" +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || date -u -r "$((NOW + 86400))" +%Y-%m-%dT%H:%M:%SZ)
    printf '7.0\t%s\t62.0\t%s' "$iso5" "$iso7" >"$CACHE_FILE"
    eval 'get_api_session_data() { return 1; }'
    render_claude "$(claude_json 4 $((NOW + 3600)) 60 $((NOW + 86400)))"
    [[ "$DATA_SESSION_PCT" == "7" ]]
    [[ "$DATA_WEEKLY_PCT" == "62" ]]
    [[ "$DATA_SESSION_PCT_STALE" == "0" ]]
}

@test "account: a held lock skips the write but still shows the shared reading" {
    eval 'get_api_session_data() { return 1; }'
    local r5=$((NOW + 3600)) r7=$((NOW + 86400))
    render_claude "$(claude_json 8 $r5 66 $r7)"
    mkdir "$_TMP_DIR/claude-account.lock"
    render_claude "$(claude_json 2 $r5 50 $r7)"
    [[ "$DATA_SESSION_PCT" == "8" ]]
    rmdir "$_TMP_DIR/claude-account.lock"
}

@test "account: a lock left by a killed render is reclaimed" {
    eval 'get_api_session_data() { return 1; }'
    mkdir "$_TMP_DIR/claude-account.lock"
    set_file_mtime "$_TMP_DIR/claude-account.lock" "$((NOW - 60))"
    render_claude "$(claude_json 12 $((NOW + 3600)) 40 $((NOW + 86400)))"
    [ -f "$(claude_account_file)" ]
    [ ! -d "$_TMP_DIR/claude-account.lock" ]
}

@test "account: two Claude accounts keep separate readings" {
    eval 'get_api_session_data() { return 1; }'
    local r5=$((NOW + 3600)) r7=$((NOW + 86400))
    _ACCOUNT_SUFFIX="-111"
    render_claude "$(claude_json 30 $r5 80 $r7)"
    _ACCOUNT_SUFFIX="-222"
    render_claude "$(claude_json 1 $r5 10 $r7)"
    [[ "$DATA_SESSION_PCT" == "1" ]]
    [ -f "$(usage_state_dir)/claude-111" ]
    [ -f "$(usage_state_dir)/claude-222" ]
}

@test "account: a reading nobody refreshed for a while is approximate" {
    eval 'get_api_session_data() { return 1; }'
    mkdir -p "$(usage_state_dir)"
    printf '6|%s|%s\t61|%s|%s\n' "$((NOW + 3600))" "$((NOW - 2000))" "$((NOW + 86400))" "$((NOW - 2000))" >"$(claude_account_file)"
    render_claude '{"model":{"id":"claude-opus-5-5"}}'
    [[ "$DATA_SESSION_PCT" == "6" ]]
    [[ "$DATA_SESSION_PCT_STALE" == "1" ]]
    [[ "$DATA_WEEKLY_PCT_STALE" == "1" ]]
}

@test "statusline: a quiet session renders the account's newer reading" {
    mkdir -p "$HOME/.claude"
    printf 'components=model,usage,weekly\ntheme=none\n' >"$HOME/.claude/statusline.conf"
    local r5=$((NOW + 3600)) r7=$((NOW + 86400))
    env TMPDIR="$BATS_TEST_TMPDIR" COLUMNS=200 bash "$STATUSLINE" <<<"$(claude_json 5 $r5 61 $r7)" >/dev/null
    run env TMPDIR="$BATS_TEST_TMPDIR" COLUMNS=200 bash "$STATUSLINE" <<<"$(claude_json 4 $r5 60 $r7)"
    [ "$status" -eq 0 ]
    [[ "$output" == "opus-5.5 | 5%/61%" ]]
}

# =========================================================================
# Icons per plan
# =========================================================================

render_icon() { # model
    run env TMPDIR="$BATS_TEST_TMPDIR" COLUMNS=200 bash "$STATUSLINE" \
        <<<'{"model":{"id":"'"$1"'","display_name":"'"$1"'"},"session_id":"si"}'
}

@test "icons: each plan shows its own icon, Claude keeps the default" {
    openai_login
    muse_login
    mkdir -p "$HOME/.claude"
    printf 'components=model\ntheme=none\nicon=A\\\nicon_openai=֍\nicon_muse=∞\n' >"$HOME/.claude/statusline.conf"
    body '{"rate_limit":null}'
    render_icon gpt-6.1-sol-fast
    [[ "$output" == "֍ gpt-6.1-sol-fast" ]]
    render_icon muse-spark-1.3
    [[ "$output" == "∞ muse-spark-1.3" ]]
    render_icon claude-opus-5-5
    [[ "$output" == 'A\ claude-opus-5-5' ]]
}

@test "icons: icon_claude overrides the default for Claude only" {
    mkdir -p "$HOME/.claude"
    printf 'components=model\ntheme=none\nicon=*\nicon_claude=✻\n' >"$HOME/.claude/statusline.conf"
    body '{"rate_limit":null}'
    render_icon claude-opus-5-5
    [[ "$output" == "✻ claude-opus-5-5" ]]
    render_icon kimi-k3
    [[ "$output" == "* kimi-k3" ]]
}

@test "icons: no per-plan icon set keeps the single icon everywhere" {
    mkdir -p "$HOME/.claude"
    printf 'components=model\ntheme=none\nicon=A\\\n' >"$HOME/.claude/statusline.conf"
    body '{"rate_limit":null}'
    render_icon gpt-6.1-sol
    [[ "$output" == 'A\ gpt-6.1-sol' ]]
}
