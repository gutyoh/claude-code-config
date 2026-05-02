# settings.sh -- IDE hook, file suggestion, statusline, and agent teams settings configuration
# Path: lib/setup/settings.sh
# Sourced by setup.sh — do not execute directly.

configure_ide_hook() {
    if python3 - "${SETTINGS_JSON}" <<'PYTHON_CHECK' 2>/dev/null; then
import json
import sys
try:
    with open(sys.argv[1]) as f:
        data = json.load(f)
    hooks = data.get('hooks', {}).get('PreToolUse', [])
    for hook in hooks:
        if hook.get('matcher') == 'mcp__ide__getDiagnostics':
            sys.exit(0)
    sys.exit(1)
except Exception:
    sys.exit(1)
PYTHON_CHECK
        echo "  ✓ IDE diagnostics hook already configured"
    else
        echo "  Adding IDE diagnostics hook to existing settings..."
        python3 - "${SETTINGS_JSON}" <<'PYTHON_SCRIPT'
import json
import sys

settings_file = sys.argv[1]

try:
    with open(settings_file) as f:
        data = json.load(f)

    if 'hooks' not in data:
        data['hooks'] = {}
    if 'PreToolUse' not in data['hooks']:
        data['hooks']['PreToolUse'] = []

    ide_hook = {
        "matcher": "mcp__ide__getDiagnostics",
        "hooks": [
            {
                "type": "command",
                "command": "~/.claude/hooks/open-file-in-ide.sh"
            }
        ]
    }

    existing = False
    for hook in data['hooks']['PreToolUse']:
        if hook.get('matcher') == 'mcp__ide__getDiagnostics':
            existing = True
            break

    if not existing:
        data['hooks']['PreToolUse'].append(ide_hook)

    with open(settings_file, 'w') as f:
        json.dump(data, f, indent=2)

    print("  ✓ IDE diagnostics hook added")
    sys.exit(0)
except Exception as e:
    print(f"  ⚠ Failed to add hook: {e}", file=sys.stderr)
    sys.exit(1)
PYTHON_SCRIPT
    fi
}

configure_file_suggestion() {
    if python3 - "${SETTINGS_JSON}" <<'PYTHON_CHECK' 2>/dev/null; then
import json
import sys
try:
    with open(sys.argv[1]) as f:
        data = json.load(f)
    if 'fileSuggestion' in data:
        sys.exit(0)
    sys.exit(1)
except Exception:
    sys.exit(1)
PYTHON_CHECK
        echo "  ✓ File suggestion already configured"
    else
        echo "  Adding file suggestion to settings..."
        python3 - "${SETTINGS_JSON}" <<'PYTHON_SCRIPT'
import json
import sys

settings_file = sys.argv[1]

try:
    with open(settings_file) as f:
        data = json.load(f)

    data['fileSuggestion'] = {
        "type": "command",
        "command": "~/.claude/scripts/file-suggestion.sh"
    }

    with open(settings_file, 'w') as f:
        json.dump(data, f, indent=2)

    print("  ✓ File suggestion configured")
    sys.exit(0)
except Exception as e:
    print(f"  ⚠ Failed to add file suggestion: {e}", file=sys.stderr)
    sys.exit(1)
PYTHON_SCRIPT
    fi
}

configure_agent_teams() {
    if [[ "${INSTALL_AGENT_TEAMS}" == "true" ]]; then
        if python3 - "${SETTINGS_JSON}" <<'PYTHON_CHECK' 2>/dev/null; then
import json
import sys
try:
    with open(sys.argv[1]) as f:
        data = json.load(f)
    if data.get('env', {}).get('CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS') == '1':
        sys.exit(0)
    sys.exit(1)
except Exception:
    sys.exit(1)
PYTHON_CHECK
            echo "  ✓ Agent teams already enabled"
        else
            echo "  Adding agent teams env to settings..."
            python3 - "${SETTINGS_JSON}" <<'PYTHON_SCRIPT'
import json
import sys

settings_file = sys.argv[1]

try:
    with open(settings_file) as f:
        data = json.load(f)

    data.setdefault('env', {})['CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS'] = '1'

    with open(settings_file, 'w') as f:
        json.dump(data, f, indent=2)

    print("  ✓ Agent teams enabled")
    sys.exit(0)
except Exception as e:
    print(f"  ⚠ Failed to enable agent teams: {e}", file=sys.stderr)
    sys.exit(1)
PYTHON_SCRIPT
        fi
    else
        python3 - "${SETTINGS_JSON}" <<'PYTHON_SCRIPT'
import json
import sys

settings_file = sys.argv[1]

try:
    with open(settings_file) as f:
        data = json.load(f)

    env = data.get('env', {})
    if 'CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS' in env:
        del env['CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS']
        if not env:
            data.pop('env', None)
        with open(settings_file, 'w') as f:
            json.dump(data, f, indent=2)
        print("  ✓ Agent teams disabled (removed from settings)")
    else:
        print("  ⊘ Agent teams not enabled (nothing to remove)")
    sys.exit(0)
except Exception as e:
    print(f"  ⚠ Failed to disable agent teams: {e}", file=sys.stderr)
    sys.exit(1)
PYTHON_SCRIPT
    fi
}

configure_proxy_path() {
    local bin_dir="${REPO_DIR}/bin"
    local marker="# claude-code-config: proxy launcher PATH"

    # Detect shell profile
    local shell_profile=""
    case "${SHELL:-}" in
        */zsh) shell_profile="${HOME}/.zshrc" ;;
        */bash) shell_profile="${HOME}/.bashrc" ;;
        *) shell_profile="${HOME}/.profile" ;;
    esac

    if [[ ! -f "${shell_profile}" ]]; then
        touch "${shell_profile}"
    fi

    # Check if already configured (with any path — handles repo moves)
    if grep -qF "${marker}" "${shell_profile}" 2>/dev/null; then
        # Extract the current path from the existing line
        local existing_path
        existing_path="$(grep -A1 "${marker}" "${shell_profile}" | grep 'export PATH=' | head -1 | sed 's/.*PATH="\(.*\)\/bin:.*/\1/')"

        if [[ "${existing_path}" == "${REPO_DIR}" ]]; then
            echo "  ✓ Proxy launcher PATH already configured in ${shell_profile}"
        else
            echo "  ↻ Updating proxy launcher PATH (repo moved)..."
            # Remove old marker + export line, then re-add
            local tmp
            tmp="$(mktemp)"
            awk -v marker="${marker}" '
                $0 == marker { skip=1; next }
                skip && /^export PATH=/ { skip=0; next }
                { skip=0; print }
            ' "${shell_profile}" >"${tmp}"
            mv "${tmp}" "${shell_profile}"

            printf '\n%s\nexport PATH="%s:$PATH"\n' "${marker}" "${bin_dir}" >>"${shell_profile}"
            echo "  ✓ Proxy launcher PATH updated in ${shell_profile}"
            echo "    Old: ${existing_path}/bin"
            echo "    New: ${bin_dir}"
        fi
    else
        printf '\n%s\nexport PATH="%s:$PATH"\n' "${marker}" "${bin_dir}" >>"${shell_profile}"
        echo "  ✓ Proxy launcher PATH added to ${shell_profile}"
    fi

    configure_claude_shortcuts "${shell_profile}"

    echo ""
    echo "  Run 'source ${shell_profile}' or open a new terminal, then:"
    echo "    claude --help"
    echo "    claude -a"
    echo "    clp -a"
    echo "    claude-proxy -p antigravity --models"
}

configure_claude_shortcuts() {
    local shell_profile="$1"
    local begin_marker="# claude-code-config: claude launch shortcuts"
    local end_marker="# claude-code-config: end claude launch shortcuts"
    local tmp

    if grep -qF "${begin_marker}" "${shell_profile}" 2>/dev/null; then
        tmp="$(mktemp)"
        awk -v begin="${begin_marker}" -v end="${end_marker}" '
            $0 == begin { skip=1; next }
            $0 == end { skip=0; next }
            !skip { print }
        ' "${shell_profile}" >"${tmp}"
        mv "${tmp}" "${shell_profile}"
    fi

    cat >>"${shell_profile}" <<'EOF'

# claude-code-config: claude launch shortcuts
claude() {
  case "${1:-}" in
    -a|--unsafe|--bypass|-adskp)
      shift
      command claude --dangerously-skip-permissions "$@"
      ;;
    *)
      command claude --allow-dangerously-skip-permissions "$@"
      ;;
  esac
}

clp() {
  local model="${CLAUDE_PROXY_MODEL:-gpt-5.5(high)}"

  case "${1:-}" in
    -a|--unsafe|--bypass|-adskp)
      shift
      claude-proxy --no-validate -m "$model" -- --dangerously-skip-permissions "$@"
      ;;
    *)
      claude-proxy --no-validate -m "$model" -- --allow-dangerously-skip-permissions "$@"
      ;;
  esac
}
# claude-code-config: end claude launch shortcuts
EOF

    echo "  ✓ Claude launch shortcuts configured in ${shell_profile}"
}

configure_statusline() {
    if python3 - "${SETTINGS_JSON}" <<'PYTHON_CHECK' 2>/dev/null; then
import json
import sys
try:
    with open(sys.argv[1]) as f:
        data = json.load(f)
    if 'statusLine' in data:
        sys.exit(0)
    sys.exit(1)
except Exception:
    sys.exit(1)
PYTHON_CHECK
        echo "  ✓ Statusline already configured"
    else
        echo "  Adding statusline to settings..."
        python3 - "${SETTINGS_JSON}" <<'PYTHON_SCRIPT'
import json
import sys

settings_file = sys.argv[1]

try:
    with open(settings_file) as f:
        data = json.load(f)

    data['statusLine'] = {
        "type": "command",
        "command": "~/.claude/scripts/statusline.sh",
        "padding": 0
    }

    with open(settings_file, 'w') as f:
        json.dump(data, f, indent=2)

    print("  ✓ Statusline configured")
    sys.exit(0)
except Exception as e:
    print(f"  ⚠ Failed to add statusline: {e}", file=sys.stderr)
    sys.exit(1)
PYTHON_SCRIPT
    fi
}
