#!/usr/bin/env bats
# cc-status.bats
# Path: tests/cc-status.bats
#
# bats-core tests for the Claude Code service status component:
#   status.sh   — label mapping, cache age, SWR orchestration
#   color.sh    — get_cc_status_color()
#   components.sh — render_component_cc_status()
#
# Run: bats tests/cc-status.bats
#      make test

MODULES_DIR="$BATS_TEST_DIRNAME/../.claude/scripts/lib/statusline"

setup() {
    # _TMP_DIR must be set BEFORE sourcing status.sh (readonly STATUS_CACHE_FILE uses it)
    _TMP_DIR="$BATS_TEST_TMPDIR"
    PLATFORM="macos"

    # Data globals
    DATA_CC_STATUS=""
    DATA_SESSION_PCT="--"
    DATA_SESSION_PCT_STALE=0

    # Config globals
    CONF_COMPONENTS="model,usage,cc_status,email"
    CONF_CC_STATUS_POSITION="inline"
    CONF_CC_STATUS_VISIBILITY="always"
    CONF_CC_STATUS_COLOR="full"
    CONF_COLOR_SCOPE="percentage"
    CONF_COMPACT="true"
    CONF_BAR_STYLE="text"
    IS_WIDE="true"

    # Color globals (dark theme)
    COLOR_OK=$'\033[0;34m'
    COLOR_CAUTION=$'\033[0;33m'
    COLOR_WARN=$'\033[38;5;208m'
    COLOR_CRIT=$'\033[0;31m'
    COLOR_RESET=$'\033[0m'

    # Source modules under test
    source "$MODULES_DIR/status.sh"
    source "$MODULES_DIR/color.sh"
    source "$MODULES_DIR/components.sh"

    # Clean slate
    rm -f "${STATUS_CACHE_FILE}" "${STATUS_CACHE_FILE}.tmp."*
}

teardown() {
    rm -f "${STATUS_CACHE_FILE}" "${STATUS_CACHE_FILE}.tmp."*
}

# Portable helper: set file mtime to a target epoch (works on macOS + Linux)
set_file_mtime() {
    local file="$1" target_epoch="$2"
    python3 -c "import os,sys; os.utime(sys.argv[1], (int(sys.argv[2]), int(sys.argv[2])))" "$file" "$target_epoch"
}

# ============================================================
# _map_status_label — API status to display label mapping
# (Atlassian Statuspage has exactly 5 component statuses)
# ============================================================

@test "label: operational → on" {
    [[ "$(_map_status_label "operational")" == "on" ]]
}

@test "label: degraded_performance → degraded" {
    [[ "$(_map_status_label "degraded_performance")" == "degraded" ]]
}

@test "label: partial_outage → partial" {
    [[ "$(_map_status_label "partial_outage")" == "partial" ]]
}

@test "label: major_outage → outage" {
    [[ "$(_map_status_label "major_outage")" == "outage" ]]
}

@test "label: under_maintenance → maintenance" {
    [[ "$(_map_status_label "under_maintenance")" == "maintenance" ]]
}

@test "label: unknown value → empty string" {
    local result
    result=$(_map_status_label "something_unexpected")
    [[ -z "$result" ]]
}

# ============================================================
# _status_cache_age — cache file age calculation
# ============================================================

@test "cache age: 999999 when file does not exist" {
    rm -f "${STATUS_CACHE_FILE}"
    local age
    age=$(_status_cache_age)
    [[ "$age" -eq 999999 ]]
}

@test "cache age: ~0 for freshly created file" {
    echo "on" > "${STATUS_CACHE_FILE}"
    local age
    age=$(_status_cache_age)
    [[ "$age" -ge 0 && "$age" -le 2 ]]
}

@test "cache age: correct value for aged file" {
    echo "on" > "${STATUS_CACHE_FILE}"
    local target_ts=$(( $(date +%s) - 120 ))
    set_file_mtime "${STATUS_CACHE_FILE}" "$target_ts"
    local age
    age=$(_status_cache_age)
    [[ "$age" -ge 118 && "$age" -le 125 ]]
}

# ============================================================
# collect_service_status — SWR cache orchestration
# ============================================================

@test "collect: skips when cc_status not in CONF_COMPONENTS" {
    CONF_COMPONENTS="model,usage,email"
    DATA_CC_STATUS="untouched"
    collect_service_status
    [[ "$DATA_CC_STATUS" == "untouched" ]]
}

@test "collect: serves fresh cache immediately" {
    echo "degraded" > "${STATUS_CACHE_FILE}"
    collect_service_status
    [[ "$DATA_CC_STATUS" == "degraded" ]]
}

@test "collect: fresh cache does NOT trigger fetch" {
    echo "on" > "${STATUS_CACHE_FILE}"
    # Override fetch to detect if called
    _fetch_and_cache_status() { echo "FETCH_CALLED"; return 0; }
    collect_service_status
    # If fetch was NOT called, DATA_CC_STATUS comes from cache ("on")
    [[ "$DATA_CC_STATUS" == "on" ]]
}

@test "collect: stale cache + fetch succeeds → uses fresh data" {
    echo "on" > "${STATUS_CACHE_FILE}"
    local target_ts=$(( $(date +%s) - 400 ))
    set_file_mtime "${STATUS_CACHE_FILE}" "$target_ts"
    # Mock fetch returning new status
    _fetch_and_cache_status() { echo "outage"; }
    collect_service_status
    [[ "$DATA_CC_STATUS" == "outage" ]]
}

@test "collect: stale cache + fetch fails → serves stale (SWR)" {
    echo "partial" > "${STATUS_CACHE_FILE}"
    # Age past TTL (300s) but within MAX_STALE (900s)
    local target_ts=$(( $(date +%s) - 400 ))
    set_file_mtime "${STATUS_CACHE_FILE}" "$target_ts"
    _fetch_and_cache_status() { return 1; }
    collect_service_status
    [[ "$DATA_CC_STATUS" == "partial" ]]
}

@test "collect: expired cache (>900s) + fetch fails → empty" {
    echo "outage" > "${STATUS_CACHE_FILE}"
    # Age past MAX_STALE (900s)
    local target_ts=$(( $(date +%s) - 1000 ))
    set_file_mtime "${STATUS_CACHE_FILE}" "$target_ts"
    _fetch_and_cache_status() { return 1; }
    collect_service_status
    [[ -z "$DATA_CC_STATUS" ]]
}

@test "collect: no cache file + fetch fails → empty" {
    rm -f "${STATUS_CACHE_FILE}"
    _fetch_and_cache_status() { return 1; }
    collect_service_status
    [[ -z "$DATA_CC_STATUS" ]]
}

@test "collect: reads each status label from cache correctly" {
    for label in on degraded partial outage maintenance; do
        echo "$label" > "${STATUS_CACHE_FILE}"
        DATA_CC_STATUS=""
        collect_service_status
        [[ "$DATA_CC_STATUS" == "$label" ]]
    done
}

# ============================================================
# get_cc_status_color — status label to ANSI color mapping
# ============================================================

@test "color: 'on' returns no color (empty)" {
    local result
    result=$(get_cc_status_color "on")
    [[ -z "$result" ]]
}

@test "color: 'degraded' → COLOR_CAUTION (yellow)" {
    local result
    result=$(get_cc_status_color "degraded")
    [[ "$result" == "$COLOR_CAUTION" ]]
}

@test "color: 'partial' → COLOR_WARN (orange)" {
    local result
    result=$(get_cc_status_color "partial")
    [[ "$result" == "$COLOR_WARN" ]]
}

@test "color: 'outage' → COLOR_CRIT (red)" {
    local result
    result=$(get_cc_status_color "outage")
    [[ "$result" == "$COLOR_CRIT" ]]
}

@test "color: 'maintenance' → COLOR_CRIT (red)" {
    local result
    result=$(get_cc_status_color "maintenance")
    [[ "$result" == "$COLOR_CRIT" ]]
}

# ============================================================
# render_component_cc_status — inline component rendering
# ============================================================

@test "render: empty when DATA_CC_STATUS is empty" {
    DATA_CC_STATUS=""
    local result
    result=$(render_component_cc_status)
    [[ -z "$result" ]]
}

@test "render: empty when position=newline (handled by main)" {
    DATA_CC_STATUS="on"
    CONF_CC_STATUS_POSITION="newline"
    local result
    result=$(render_component_cc_status)
    [[ -z "$result" ]]
}

@test "render: hidden when problem_only + status is 'on'" {
    DATA_CC_STATUS="on"
    CONF_CC_STATUS_VISIBILITY="problem_only"
    local result
    result=$(render_component_cc_status)
    [[ -z "$result" ]]
}

@test "render: shown when problem_only + status is 'degraded'" {
    DATA_CC_STATUS="degraded"
    CONF_CC_STATUS_VISIBILITY="problem_only"
    local result
    result=$(render_component_cc_status)
    [[ "$result" == *"degraded"* ]]
}

@test "render: shown when problem_only + status is 'outage'" {
    DATA_CC_STATUS="outage"
    CONF_CC_STATUS_VISIBILITY="problem_only"
    local result
    result=$(render_component_cc_status)
    [[ "$result" == *"outage"* ]]
}

@test "render: plain label when color=none" {
    DATA_CC_STATUS="outage"
    CONF_CC_STATUS_COLOR="none"
    local result
    result=$(render_component_cc_status)
    [[ "$result" == "outage" ]]
}

@test "render: colored label when color=full + outage" {
    DATA_CC_STATUS="outage"
    CONF_CC_STATUS_COLOR="full"
    local result
    result=$(render_component_cc_status)
    [[ "$result" == "${COLOR_CRIT}outage${COLOR_RESET}" ]]
}

@test "render: colored label when color=full + degraded" {
    DATA_CC_STATUS="degraded"
    CONF_CC_STATUS_COLOR="full"
    local result
    result=$(render_component_cc_status)
    [[ "$result" == "${COLOR_CAUTION}degraded${COLOR_RESET}" ]]
}

@test "render: no color wrap for 'on' even with color=full" {
    DATA_CC_STATUS="on"
    CONF_CC_STATUS_COLOR="full"
    CONF_CC_STATUS_VISIBILITY="always"
    local result
    result=$(render_component_cc_status)
    # 'on' has no color mapping, so should be plain
    [[ "$result" == "on" ]]
}

@test "render: shows 'on' when visibility=always" {
    DATA_CC_STATUS="on"
    CONF_CC_STATUS_VISIBILITY="always"
    CONF_CC_STATUS_COLOR="none"
    local result
    result=$(render_component_cc_status)
    [[ "$result" == "on" ]]
}

# ============================================================
# Code patterns — verify conventions from PR #8
# ============================================================

@test "status.sh uses atomic write (temp+mv pattern)" {
    local status_file="$BATS_TEST_DIRNAME/../.claude/scripts/lib/statusline/status.sh"
    grep -q 'mv -f.*tmp.*STATUS_CACHE_FILE' "$status_file"
}

@test "status.sh uses UID-scoped _TMP_DIR for cache path" {
    local status_file="$BATS_TEST_DIRNAME/../.claude/scripts/lib/statusline/status.sh"
    grep -q '_TMP_DIR.*/status-cache' "$status_file"
}

@test "status.sh does NOT use hardcoded /tmp path" {
    local status_file="$BATS_TEST_DIRNAME/../.claude/scripts/lib/statusline/status.sh"
    ! grep -q 'STATUS_CACHE_FILE="/tmp/' "$status_file"
}

# ============================================================
# Integration: status.claude.com API (requires network)
# ============================================================

_has_network() {
    curl -s --max-time 3 "https://status.claude.com/api/v2/summary.json" > /dev/null 2>&1
}

@test "integration: status.claude.com has 'Claude Code' component" {
    _has_network || skip "No network access"
    local response
    response=$(curl -s --max-time 5 "${STATUS_API_URL}")
    local cc_status
    cc_status=$(echo "$response" | jq -r '.components[] | select(.name == "Claude Code") | .status')
    [[ -n "$cc_status" ]]
}

@test "integration: API status maps to a known label" {
    _has_network || skip "No network access"
    local response
    response=$(curl -s --max-time 5 "${STATUS_API_URL}")
    local raw_status
    raw_status=$(echo "$response" | jq -r '.components[] | select(.name == "Claude Code") | .status')
    local label
    label=$(_map_status_label "$raw_status")
    [[ -n "$label" ]]
    # Must be one of our 5 known labels
    [[ "$label" == "on" || "$label" == "degraded" || "$label" == "partial" || "$label" == "outage" || "$label" == "maintenance" ]]
}

@test "integration: _fetch_and_cache_status writes cache file" {
    _has_network || skip "No network access"
    rm -f "${STATUS_CACHE_FILE}"
    _fetch_and_cache_status > /dev/null
    [[ -f "${STATUS_CACHE_FILE}" ]]
    local content
    content=$(cat "${STATUS_CACHE_FILE}")
    [[ "$content" == "on" || "$content" == "degraded" || "$content" == "partial" || "$content" == "outage" || "$content" == "maintenance" ]]
}

@test "integration: no leftover .tmp files after fetch" {
    _has_network || skip "No network access"
    _fetch_and_cache_status > /dev/null 2>&1 || true
    local tmp_count
    tmp_count=$(find "$BATS_TEST_TMPDIR" -name "status-cache.tmp.*" 2>/dev/null | wc -l | tr -d ' ')
    [[ "$tmp_count" -eq 0 ]]
}
