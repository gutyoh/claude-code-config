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

# Resolve the user's LOGIN shell — the one whose rc file they actually use.
#
# $SHELL is the obvious candidate and the wrong one: it is an ordinary
# environment variable inherited from whatever spawned the process, and no
# shell corrects it on startup. `SHELL=/bin/made-up fish -c 'echo $SHELL'`
# prints /bin/made-up. So a fish user whose terminal was launched with
# SHELL=zsh gets their shortcuts written to ~/.zshrc, which fish never reads,
# and the install silently does nothing useful.
#
# The password database is authoritative. Order: explicit override, then the
# platform's user database, then $SHELL as a last resort.
detect_login_shell() {
    if [[ -n "${CLAUDE_CONFIG_SHELL:-}" ]]; then
        printf '%s\n' "${CLAUDE_CONFIG_SHELL}"
        return
    fi

    local found=""

    # macOS: OpenDirectory, not /etc/passwd.
    if command -v dscl >/dev/null 2>&1; then
        found="$(dscl . -read "/Users/${USER}" UserShell 2>/dev/null | awk '{print $2}')"
    fi

    # Linux / BSD: nsswitch-aware lookup, then the flat file.
    if [[ -z "${found}" ]] && command -v getent >/dev/null 2>&1; then
        found="$(getent passwd "${USER}" 2>/dev/null | cut -d: -f7)"
    fi
    if [[ -z "${found}" && -r /etc/passwd ]]; then
        found="$(awk -F: -v u="${USER}" '$1 == u { print $7 }' /etc/passwd 2>/dev/null | head -1)"
    fi

    # Last resort. Better than nothing, but see the caveat above.
    [[ -z "${found}" ]] && found="${SHELL:-}"

    printf '%s\n' "${found}"
}

configure_proxy_path() {
    local bin_dir="${REPO_DIR}/bin"
    local marker="# claude-code-config: proxy launcher PATH"

    local login_shell
    login_shell="$(detect_login_shell)"

    # fish is not POSIX: `export VAR=x` and shell functions are syntax errors
    # there, so it gets its own installer writing native fish files instead of
    # appending to a profile.
    case "${login_shell}" in
        */fish)
            echo "  Detected login shell: ${login_shell}"
            configure_fish_shell "${bin_dir}"
            return
            ;;
    esac

    # Detect shell profile
    local shell_profile=""
    case "${login_shell}" in
        */zsh) shell_profile="${HOME}/.zshrc" ;;
        */bash) shell_profile="${HOME}/.bashrc" ;;
        *) shell_profile="${HOME}/.profile" ;;
    esac
    echo "  Detected login shell: ${login_shell:-unknown} -> ${shell_profile}"

    # bash reads ~/.bashrc for non-login interactive shells and ~/.bash_profile
    # for login shells. Linux terminals open the former; macOS Terminal.app and
    # iTerm2 open the LATTER. So a block written only to ~/.bashrc silently
    # never loads on macOS — the install reports success and the user gets no
    # `claude` function. Bridge them, which is the conventional fix.
    case "${login_shell}" in
        */bash) ensure_bash_profile_sources_bashrc ;;
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
        # Only rewrite when BOTH markers are present. With a begin marker and no
        # end marker — a hand-edit, an interrupted write, a partial paste — the
        # awk below would skip from the marker to EOF and silently delete
        # everything after it. This edits the user's shell profile, so the
        # failure mode is losing their exports and aliases with no warning.
        if grep -qF "${end_marker}" "${shell_profile}" 2>/dev/null; then
            tmp="$(mktemp)"
            awk -v begin="${begin_marker}" -v end="${end_marker}" '
                $0 == begin { skip=1; next }
                $0 == end { skip=0; next }
                !skip { print }
            ' "${shell_profile}" >"${tmp}"
            mv "${tmp}" "${shell_profile}"
        else
            local backup="${shell_profile}.claude-code-config.bak"
            cp "${shell_profile}" "${backup}" 2>/dev/null || true
            echo "  ⚠ ${shell_profile} has the shortcuts begin marker but no end marker."
            echo "    Refusing to rewrite it — that would delete everything after the marker."
            echo "    Backup: ${backup}"
            echo "    Remove the stale block by hand, then re-run setup."
            return 0
        fi
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

# No `local`: this block is written to ~/.profile for any shell that is not
# bash or zsh, and `local` is not in POSIX — it is a widely-implemented
# extension, not a guarantee. Expanding the parameter inline needs no variable,
# so nothing leaks into the caller's environment either.
clp() {
  case "${1:-}" in
    -a|--unsafe|--bypass|-adskp)
      shift
      claude-proxy --no-validate -m "${CLAUDE_PROXY_MODEL:-gpt-5.5(high)}" -- --dangerously-skip-permissions "$@"
      ;;
    *)
      claude-proxy --no-validate -m "${CLAUDE_PROXY_MODEL:-gpt-5.5(high)}" -- --allow-dangerously-skip-permissions "$@"
      ;;
  esac
}
# claude-code-config: end claude launch shortcuts
EOF

    echo "  ✓ Claude launch shortcuts configured in ${shell_profile}"
}

# fish equivalent of configure_proxy_path + configure_claude_shortcuts.
# Functions go in functions/ (autoloaded lazily, by filename); the PATH entry
# goes in conf.d/ (sourced on every shell start).
# Make ~/.bash_profile source ~/.bashrc, once, idempotently.
# Without this, anything written to .bashrc is invisible to login shells, which
# is what macOS terminals start.
ensure_bash_profile_sources_bashrc() {
    local profile="${HOME}/.bash_profile"
    local marker="# claude-code-config: load .bashrc for login shells"

    # A .bash_profile that already pulls in .bashrc by any spelling is fine.
    if [[ -f "${profile}" ]] && grep -qE '(\.|source)[[:space:]]+.*\.bashrc' "${profile}" 2>/dev/null; then
        return 0
    fi
    if [[ -f "${profile}" ]] && grep -qF "${marker}" "${profile}" 2>/dev/null; then
        return 0
    fi

    cat >>"${profile}" <<EOF

${marker}
[ -f "\${HOME}/.bashrc" ] && . "\${HOME}/.bashrc"
EOF
    echo "  ✓ ${profile} now sources ~/.bashrc (macOS terminals start login shells)"
}

configure_fish_shell() {
    local bin_dir="$1"
    local fish_dir="${XDG_CONFIG_HOME:-${HOME}/.config}/fish"
    local functions_dir="${fish_dir}/functions"
    local confd_dir="${fish_dir}/conf.d"
    local path_file="${confd_dir}/00-claude-code-config-path.fish"

    mkdir -p "${functions_dir}" "${confd_dir}"

    cat >"${path_file}" <<EOF
# claude-code-config: proxy launcher PATH
# Managed by setup.sh — regenerated on each run. fish_add_path is idempotent
# and silently skips directories that do not exist.
fish_add_path -ga ${bin_dir}
EOF

    cat >"${functions_dir}/claude.fish" <<'EOF'
function claude --description 'Claude Code with proxy launcher defaults'
    # Managed by claude-code-config setup.sh.
    # Defaults to --allow-dangerously-skip-permissions; opt in to
    # --dangerously-skip-permissions via -a / --unsafe / --bypass / -adskp.

    set -l first ""
    test (count $argv) -gt 0; and set first $argv[1]

    switch $first
        case -a --unsafe --bypass -adskp
            set -l rest
            test (count $argv) -gt 1; and set rest $argv[2..-1]
            command claude --dangerously-skip-permissions $rest
        case '*'
            command claude --allow-dangerously-skip-permissions $argv
    end
end
EOF

    cat >"${functions_dir}/clp.fish" <<'EOF'
function clp --description 'Claude proxy with model'
    # Managed by claude-code-config setup.sh.

    set -l model 'gpt-5.5(high)'
    test -n "$CLAUDE_PROXY_MODEL"; and set model $CLAUDE_PROXY_MODEL

    set -l first ""
    test (count $argv) -gt 0; and set first $argv[1]

    switch $first
        case -a --unsafe --bypass -adskp
            set -l rest
            test (count $argv) -gt 1; and set rest $argv[2..-1]
            claude-proxy --no-validate -m $model -- --dangerously-skip-permissions $rest
        case '*'
            claude-proxy --no-validate -m $model -- --allow-dangerously-skip-permissions $argv
    end
end
EOF

    echo "  ✓ Proxy launcher PATH added to ${path_file}"
    echo "  ✓ Claude launch shortcuts configured in ${functions_dir}"
    echo ""
    echo "  Open a new terminal (or 'exec fish'), then:"
    echo "    claude --help"
    echo "    claude -a"
    echo "    clp -a"
    echo "    claude-proxy -p antigravity --models"
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

configure_claude_sync_hooks() {
    # Resolves INSTALL_CLAUDE_SYNC=auto by detecting `claude-sync` on PATH.
    # Idempotently adds SessionStart (cc-sync-pull) and SessionEnd
    # (cc-sync-push) hook entries to ${SETTINGS_JSON}, or removes them
    # when INSTALL_CLAUDE_SYNC=no.
    local mode="${INSTALL_CLAUDE_SYNC:-auto}"

    if [[ "${mode}" == "auto" ]]; then
        if command -v claude-sync >/dev/null 2>&1; then
            mode="yes"
        else
            mode="no"
        fi
    fi

    if [[ "${mode}" == "yes" ]]; then
        if python3 - "${SETTINGS_JSON}" <<'PYTHON_CHECK' 2>/dev/null; then
import json
import sys
try:
    with open(sys.argv[1]) as f:
        data = json.load(f)
    hooks = data.get('hooks', {})
    start = hooks.get('SessionStart', [])
    end = hooks.get('SessionEnd', [])
    # A hook without an explicit timeout is unbounded: Claude Code waits on it
    # for as long as it runs. Treat a timeout-less entry as needing an upgrade
    # so re-running setup repairs configs written by older versions.
    pull_present = any(
        h.get('command') == '~/.claude/hooks/cc-sync-pull.sh' and 'timeout' in h
        for entry in start for h in entry.get('hooks', [])
    )
    push_present = any(
        h.get('command') == '~/.claude/hooks/cc-sync-push.sh' and 'timeout' in h
        for entry in end for h in entry.get('hooks', [])
    )
    sys.exit(0 if pull_present and push_present else 1)
except Exception:
    sys.exit(1)
PYTHON_CHECK
            echo "  ✓ Claude-sync session hooks already configured"
        else
            echo "  Adding claude-sync session hooks to settings..."
            python3 - "${SETTINGS_JSON}" <<'PYTHON_SCRIPT'
import json
import sys

settings_file = sys.argv[1]

try:
    with open(settings_file) as f:
        data = json.load(f)

    data.setdefault('hooks', {})

    # Both hooks detach their transfer, so they return in milliseconds. The
    # timeout is a backstop against a hook that somehow blocks anyway — without
    # it Claude Code waits indefinitely and session startup stalls.
    HOOK_TIMEOUT_SEC = 10

    def entry(command):
        return {
            "hooks": [
                {
                    "type": "command",
                    "command": command,
                    "timeout": HOOK_TIMEOUT_SEC
                }
            ]
        }

    def upgrade(entries, command):
        """Add a timeout to a pre-existing entry, or append a new one."""
        for group in entries:
            for hook in group.get('hooks', []):
                if hook.get('command') == command:
                    hook.setdefault('timeout', HOOK_TIMEOUT_SEC)
                    return
        entries.append(entry(command))

    upgrade(
        data['hooks'].setdefault('SessionStart', []),
        '~/.claude/hooks/cc-sync-pull.sh',
    )
    upgrade(
        data['hooks'].setdefault('SessionEnd', []),
        '~/.claude/hooks/cc-sync-push.sh',
    )

    with open(settings_file, 'w') as f:
        json.dump(data, f, indent=2)

    print("  ✓ Claude-sync session hooks configured")
    sys.exit(0)
except Exception as e:
    print(f"  ⚠ Failed to add claude-sync hooks: {e}", file=sys.stderr)
    sys.exit(1)
PYTHON_SCRIPT
        fi

        if ! command -v claude-sync >/dev/null 2>&1; then
            echo "  ⚠ claude-sync not found on PATH — hooks will no-op until installed"
            echo "    Install with: npm install -g @tawandotorg/claude-sync"
            echo "    Then run: claude-sync init"
        fi
    else
        python3 - "${SETTINGS_JSON}" <<'PYTHON_SCRIPT'
import json
import sys

settings_file = sys.argv[1]

try:
    with open(settings_file) as f:
        data = json.load(f)

    hooks = data.get('hooks', {})
    changed = False

    for event, target in (
        ('SessionStart', '~/.claude/hooks/cc-sync-pull.sh'),
        ('SessionEnd', '~/.claude/hooks/cc-sync-push.sh'),
    ):
        entries = hooks.get(event, [])
        kept = []
        for entry in entries:
            sub = [h for h in entry.get('hooks', []) if h.get('command') != target]
            if sub:
                entry['hooks'] = sub
                kept.append(entry)
            else:
                changed = True
        if kept != entries:
            changed = True
            if kept:
                hooks[event] = kept
            else:
                hooks.pop(event, None)

    if changed:
        if hooks:
            data['hooks'] = hooks
        else:
            data.pop('hooks', None)
        with open(settings_file, 'w') as f:
            json.dump(data, f, indent=2)
        print("  ✓ Claude-sync session hooks removed")
    else:
        print("  ⊘ Claude-sync session hooks not present (nothing to remove)")
    sys.exit(0)
except Exception as e:
    print(f"  ⚠ Failed to remove claude-sync hooks: {e}", file=sys.stderr)
    sys.exit(1)
PYTHON_SCRIPT
    fi
}
