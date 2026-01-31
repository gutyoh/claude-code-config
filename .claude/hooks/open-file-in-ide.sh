#!/usr/bin/env bash
# open-file-in-ide.sh
# Path: .claude/hooks/open-file-in-ide.sh
#
# Opens a file in the user's IDE before calling mcp__ide__getDiagnostics.
# This works around JetBrains bug #3085 where diagnostics timeout if the file
# is not the currently active tab in the IDE.
#
# Usage:     Called by PreToolUse hook for mcp__ide__getDiagnostics
# Input:     Receives JSON via stdin containing tool_input.uri
# Output:    Opens file in IDE, returns 0 on success
# Platforms: macOS, Linux
#
# Configuration:
#   Set CLAUDE_IDE environment variable to force a specific IDE:
#     export CLAUDE_IDE="code-insiders"
#     export CLAUDE_IDE="pycharm"
#     export CLAUDE_IDE="cursor"
#     export CLAUDE_IDE="windsurf"
#
# Supported IDEs (auto-detected):
#   JetBrains: pycharm, idea, webstorm, phpstorm, goland, rider, clion, rubymine
#   VSCode:    code, code-insiders
#   Others:    cursor, windsurf, antigravity

set -uo pipefail

# --- Constants ---

# IDE definitions: "command|pgrep_pattern_1|pgrep_pattern_2"
# Order determines Tier 2 auto-detection priority
readonly IDE_DEFINITIONS=(
    "code-insiders|Code - Insiders|code-insiders"
    "code|^Code$|^code$"
    "cursor|Cursor|cursor"
    "windsurf|Windsurf|windsurf"
    "antigravity|Antigravity|antigravity"
    "pycharm|pycharm|PyCharm"
    "idea|idea|IntelliJ IDEA"
    "webstorm|webstorm|WebStorm"
    "phpstorm|phpstorm|PhpStorm"
    "goland|goland|GoLand"
    "rider|rider|Rider"
    "clion|clion|CLion"
    "rubymine|rubymine|RubyMine"
)

# --- Functions ---

open_in_ide() {
    local ide_cmd="$1"
    local file_path="$2"

    case "${ide_cmd}" in
        pycharm | idea | webstorm | phpstorm | goland | rider | clion | rubymine)
            # JetBrains IDEs use --line flag
            "${ide_cmd}" --line 1 "${file_path}" &>/dev/null &
            ;;
        code | code-insiders | cursor | windsurf | antigravity)
            # VSCode-based IDEs use simpler syntax
            "${ide_cmd}" "${file_path}" &>/dev/null &
            ;;
        *)
            # Generic fallback
            "${ide_cmd}" "${file_path}" &>/dev/null &
            ;;
    esac
}

detect_running_ide() {
    # Tier 2: Auto-detect running IDE via process list
    local file_path="$1"
    local entry ide_cmd pattern1 pattern2

    for entry in "${IDE_DEFINITIONS[@]}"; do
        IFS='|' read -r ide_cmd pattern1 pattern2 <<<"${entry}"
        if (pgrep -if "${pattern1}" &>/dev/null || pgrep -if "${pattern2}" &>/dev/null) \
            && command -v "${ide_cmd}" &>/dev/null; then
            open_in_ide "${ide_cmd}" "${file_path}"
            sleep 0.5
            return 0
        fi
    done

    return 1
}

fallback_to_available_ide() {
    # Tier 3: First available IDE command (nothing is running)
    local file_path="$1"
    local entry ide_cmd

    for entry in "${IDE_DEFINITIONS[@]}"; do
        ide_cmd="${entry%%|*}"
        if command -v "${ide_cmd}" &>/dev/null; then
            open_in_ide "${ide_cmd}" "${file_path}"
            sleep 0.5
            return 0
        fi
    done

    return 1
}

# --- Main ---

main() {
    # Read the file URI from stdin via jq
    local file_path
    file_path=$(jq -r '.tool_input.uri' | sed 's|^file://||')

    # Tier 1: Explicit user preference via CLAUDE_IDE environment variable
    if [[ -n "${CLAUDE_IDE:-}" ]]; then
        if command -v "${CLAUDE_IDE}" &>/dev/null; then
            open_in_ide "${CLAUDE_IDE}" "${file_path}"
            sleep 0.5
            exit 0
        fi
        # User-specified IDE not found, fall through to auto-detection
    fi

    # Tier 2: Auto-detect running IDE (check processes)
    detect_running_ide "${file_path}" && exit 0

    # Tier 3: Fallback to first available IDE command
    fallback_to_available_ide "${file_path}" && exit 0

    # No IDE found — exit gracefully (getDiagnostics will proceed without opening file)
    exit 0
}

main "$@"
