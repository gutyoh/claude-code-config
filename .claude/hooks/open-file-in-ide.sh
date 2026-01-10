#!/bin/bash
# open-file-in-ide.sh
# Path: .claude/hooks/open-file-in-ide.sh
#
# Opens a file in the user's IDE before calling mcp__ide__getDiagnostics.
# This works around JetBrains bug #3085 where diagnostics timeout if the file
# is not the currently active tab in the IDE.
#
# Usage: Called by PreToolUse hook for mcp__ide__getDiagnostics
# Input: Receives JSON via stdin containing tool_input.uri
# Output: Opens file in IDE, returns 0 on success
#
# Configuration:
#   Set CLAUDE_IDE environment variable to force a specific IDE:
#     export CLAUDE_IDE="code-insiders"
#     export CLAUDE_IDE="pycharm"
#     export CLAUDE_IDE="cursor"
#     export CLAUDE_IDE="windsurf"
#
# Supported IDEs (auto-detected):
#   - PyCharm (pycharm)
#   - IntelliJ IDEA (idea)
#   - VSCode (code)
#   - VSCode Insiders (code-insiders)
#   - Cursor (cursor)
#   - Windsurf (windsurf)
#   - Antigravity (antigravity)

set -e

# Read the file URI from stdin via jq
FILE_PATH=$(jq -r '.tool_input.uri' | sed 's|^file://||')

# Function to open file in a specific IDE
open_in_ide() {
    local ide_cmd="$1"
    local file_path="$2"

    case "$ide_cmd" in
        pycharm|idea|webstorm|phpstorm|goland|rider|clion|rubymine)
            # JetBrains IDEs use --line flag
            "$ide_cmd" --line 1 "$file_path" &> /dev/null &
            ;;
        code|code-insiders|cursor|windsurf|antigravity)
            # VSCode-based IDEs use simpler syntax
            "$ide_cmd" "$file_path" &> /dev/null &
            ;;
        *)
            # Generic fallback
            "$ide_cmd" "$file_path" &> /dev/null &
            ;;
    esac
}

# Tier 1: Explicit user preference via CLAUDE_IDE environment variable
if [ -n "$CLAUDE_IDE" ]; then
    if command -v "$CLAUDE_IDE" &> /dev/null; then
        open_in_ide "$CLAUDE_IDE" "$FILE_PATH"
        sleep 0.5
        exit 0
    else
        # User specified IDE not found, continue to auto-detection
        :
    fi
fi

# Tier 2: Auto-detect running IDE (check processes)
# Priority order: match currently running IDE to avoid waking up closed ones

# Check VSCode Insiders
if (pgrep -if "Code - Insiders" &> /dev/null || pgrep -if "code-insiders" &> /dev/null) && command -v code-insiders &> /dev/null; then
    open_in_ide "code-insiders" "$FILE_PATH"
    sleep 0.5
    exit 0
fi

# Check VSCode
if (pgrep -if "^Code$" &> /dev/null || pgrep -if "^code$" &> /dev/null) && command -v code &> /dev/null; then
    open_in_ide "code" "$FILE_PATH"
    sleep 0.5
    exit 0
fi

# Check Cursor
if (pgrep -if "Cursor" &> /dev/null || pgrep -if "cursor" &> /dev/null) && command -v cursor &> /dev/null; then
    open_in_ide "cursor" "$FILE_PATH"
    sleep 0.5
    exit 0
fi

# Check Windsurf
if (pgrep -if "Windsurf" &> /dev/null || pgrep -if "windsurf" &> /dev/null) && command -v windsurf &> /dev/null; then
    open_in_ide "windsurf" "$FILE_PATH"
    sleep 0.5
    exit 0
fi

# Check Antigravity
if (pgrep -if "Antigravity" &> /dev/null || pgrep -if "antigravity" &> /dev/null) && command -v antigravity &> /dev/null; then
    open_in_ide "antigravity" "$FILE_PATH"
    sleep 0.5
    exit 0
fi

# Check PyCharm
if (pgrep -if "pycharm" &> /dev/null || pgrep -if "PyCharm" &> /dev/null) && command -v pycharm &> /dev/null; then
    open_in_ide "pycharm" "$FILE_PATH"
    sleep 0.5
    exit 0
fi

# Check IntelliJ IDEA
if (pgrep -if "idea" &> /dev/null || pgrep -if "IntelliJ IDEA" &> /dev/null) && command -v idea &> /dev/null; then
    open_in_ide "idea" "$FILE_PATH"
    sleep 0.5
    exit 0
fi

# Check WebStorm
if (pgrep -if "webstorm" &> /dev/null || pgrep -if "WebStorm" &> /dev/null) && command -v webstorm &> /dev/null; then
    open_in_ide "webstorm" "$FILE_PATH"
    sleep 0.5
    exit 0
fi

# Check PhpStorm
if (pgrep -if "phpstorm" &> /dev/null || pgrep -if "PhpStorm" &> /dev/null) && command -v phpstorm &> /dev/null; then
    open_in_ide "phpstorm" "$FILE_PATH"
    sleep 0.5
    exit 0
fi

# Check GoLand
if (pgrep -if "goland" &> /dev/null || pgrep -if "GoLand" &> /dev/null) && command -v goland &> /dev/null; then
    open_in_ide "goland" "$FILE_PATH"
    sleep 0.5
    exit 0
fi

# Check Rider
if (pgrep -if "rider" &> /dev/null || pgrep -if "Rider" &> /dev/null) && command -v rider &> /dev/null; then
    open_in_ide "rider" "$FILE_PATH"
    sleep 0.5
    exit 0
fi

# Check CLion
if (pgrep -if "clion" &> /dev/null || pgrep -if "CLion" &> /dev/null) && command -v clion &> /dev/null; then
    open_in_ide "clion" "$FILE_PATH"
    sleep 0.5
    exit 0
fi

# Check RubyMine
if (pgrep -if "rubymine" &> /dev/null || pgrep -if "RubyMine" &> /dev/null) && command -v rubymine &> /dev/null; then
    open_in_ide "rubymine" "$FILE_PATH"
    sleep 0.5
    exit 0
fi

# Tier 3: Fallback to first available IDE command (nothing is running)
# Priority order: prefer modern editors first
for ide_cmd in code-insiders cursor windsurf antigravity code pycharm idea webstorm phpstorm goland rider clion rubymine; do
    if command -v "$ide_cmd" &> /dev/null; then
        open_in_ide "$ide_cmd" "$FILE_PATH"
        sleep 0.5
        exit 0
    fi
done

# No IDE found - exit gracefully (getDiagnostics will proceed without opening file)
exit 0
