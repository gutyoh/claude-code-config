# settings.sh -- IDE hook, file suggestion, and statusline settings configuration
# Path: lib/setup/settings.sh
# Sourced by setup.sh — do not execute directly.

configure_ide_hook() {
    if python3 -c "
import json
import sys
try:
    with open('${SETTINGS_JSON}') as f:
        data = json.load(f)
    hooks = data.get('hooks', {}).get('PreToolUse', [])
    for hook in hooks:
        if hook.get('matcher') == 'mcp__ide__getDiagnostics':
            sys.exit(0)
    sys.exit(1)
except Exception:
    sys.exit(1)
" 2>/dev/null; then
        echo "  ✓ IDE diagnostics hook already configured"
    else
        echo "  Adding IDE diagnostics hook to existing settings..."
        python3 <<PYTHON_SCRIPT
import json
import sys

settings_file = "${SETTINGS_JSON}"

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
    if python3 -c "
import json
import sys
try:
    with open('${SETTINGS_JSON}') as f:
        data = json.load(f)
    if 'fileSuggestion' in data:
        sys.exit(0)
    sys.exit(1)
except Exception:
    sys.exit(1)
" 2>/dev/null; then
        echo "  ✓ File suggestion already configured"
    else
        echo "  Adding file suggestion to settings..."
        python3 <<PYTHON_SCRIPT
import json
import sys

settings_file = "${SETTINGS_JSON}"

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

configure_statusline() {
    if python3 -c "
import json
import sys
try:
    with open('${SETTINGS_JSON}') as f:
        data = json.load(f)
    if 'statusLine' in data:
        sys.exit(0)
    sys.exit(1)
except Exception:
    sys.exit(1)
" 2>/dev/null; then
        echo "  ✓ Statusline already configured"
    else
        echo "  Adding statusline to settings..."
        python3 <<PYTHON_SCRIPT
import json
import sys

settings_file = "${SETTINGS_JSON}"

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
