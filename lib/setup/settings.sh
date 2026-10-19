# settings.sh -- IDE hook, file suggestion, statusline, and agent teams settings configuration
# Path: lib/setup/settings.sh
# Sourced by setup.sh — do not execute directly.

# Python before 3.15 reads, writes and prints in the system code page (cp1252
# under Git Bash on Windows): UTF-8 mode, as 3.15 defaults, unless turned off.
export PYTHONUTF8="${PYTHONUTF8:-1}"

# Copy over the file's contents instead of renaming onto it: a rename replaces a
# symlinked rc file (stow, chezmoi, home-manager) with a plain one.
_replace_contents() {
    local src="$1" dest="$2"
    cat "${src}" >"${dest}"
    rm -f "${src}"
}

write_default_settings() {
    python3 - "$1" <<'PYTHON_SCRIPT'
import json
import os
import sys

ref = os.environ.get('CLAUDE_DIR_REF', '~/.claude')
data = {"cleanupPeriodDays": 36500, "hooks": {"PreToolUse": [{
    "matcher": "mcp__ide__getDiagnostics",
    "hooks": [{"type": "command", "command": f"{ref}/hooks/open-file-in-ide.sh"}],
}]}}
with open(sys.argv[1], 'w') as f:
    json.dump(data, f, indent=2)
    f.write('\n')
PYTHON_SCRIPT
}

# The repo file doubles as this project's own settings, where the commands must
# stay "~/.claude/..." so they dedupe with the user's; rewrite only the copy.
write_repo_settings() {
    local src="$1" dest="$2"
    if [[ "${CLAUDE_DIR_REF}" == "~/.claude" ]]; then
        cat "${src}" >"${dest}"
        return
    fi
    python3 - "${src}" "${dest}" <<'PYTHON_SCRIPT'
import json
import os
import sys

ref = os.environ['CLAUDE_DIR_REF']


def rewrite(node):
    if isinstance(node, dict):
        return {k: (ref + v[len('~/.claude'):] if k == 'command' and isinstance(v, str)
                    and v.startswith('~/.claude/') else rewrite(v)) for k, v in node.items()}
    if isinstance(node, list):
        return [rewrite(v) for v in node]
    return node


with open(sys.argv[1]) as f:
    data = json.load(f)
with open(sys.argv[2], 'w') as f:
    json.dump(rewrite(data), f, indent=2)
    f.write('\n')
PYTHON_SCRIPT
}

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
import os
import sys

settings_file = sys.argv[1]
ref = os.environ.get('CLAUDE_DIR_REF', '~/.claude')

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
                "command": f"{ref}/hooks/open-file-in-ide.sh"
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

# Session naming (hooks/session-name.sh) needs one entry on each of two events,
# hooks/session-account.sh one on every session start, and
# hooks/session-remote-title.sh one on every start and prompt; an entry already
# naming a script is left as it is.
configure_session_name_hooks() {
    python3 - "${SETTINGS_JSON}" <<'PYTHON_SCRIPT'
import json
import os
import sys

settings_file = sys.argv[1]
ref = os.environ.get('CLAUDE_DIR_REF', '~/.claude')
wanted = (
    ('SessionStart', {'matcher': 'startup'}, 'session-name.sh'),
    ('UserPromptSubmit', {'matcher': ''}, 'session-name.sh'),
    ('SessionStart', {'matcher': ''}, 'session-account.sh'),
    ('SessionStart', {'matcher': ''}, 'session-remote-title.sh'),
    ('UserPromptSubmit', {'matcher': ''}, 'session-remote-title.sh'),
)

try:
    with open(settings_file) as f:
        data = json.load(f)
    hooks = data.setdefault('hooks', {})
    added = 0
    for event, extra, script in wanted:
        entries = hooks.setdefault(event, [])
        present = any(script in h.get('command', '')
                      for e in entries for h in e.get('hooks', []))
        if not present:
            entries.append({**extra, 'hooks': [{
                'type': 'command',
                'command': f'{ref}/hooks/{script}',
                'timeout': 5,
            }]})
            added += 1
    if added:
        with open(settings_file, 'w') as f:
            json.dump(data, f, indent=2)
            f.write('\n')
        print("  ✓ Session hooks added")
    else:
        print("  ✓ Session hooks already configured")
except Exception as e:
    print(f"  ⚠ Failed to add session hooks: {e}", file=sys.stderr)
    sys.exit(1)
PYTHON_SCRIPT
}

# The public-text guard (hooks/guard-public-text.sh) on every Bash call; it acts
# only once CLAUDE_LEAK_GUARD names a scanner. An entry naming it stays as it is.
configure_public_text_guard_hook() {
    python3 - "${SETTINGS_JSON}" <<'PYTHON_SCRIPT'
import json
import os
import sys

settings_file = sys.argv[1]
ref = os.environ.get('CLAUDE_DIR_REF', '~/.claude')
try:
    with open(settings_file) as f:
        data = json.load(f)
    entries = data.setdefault('hooks', {}).setdefault('PreToolUse', [])
    if any('guard-public-text.sh' in h.get('command', '')
           for e in entries for h in e.get('hooks', [])):
        print("  ✓ Public text guard hook already configured")
        sys.exit(0)
    entries.append({'matcher': 'Bash', 'hooks': [{
        'type': 'command',
        'command': f'{ref}/hooks/guard-public-text.sh',
        'timeout': 30,
    }]})
    with open(settings_file, 'w') as f:
        json.dump(data, f, indent=2)
        f.write('\n')
    print("  ✓ Public text guard hook added")
except Exception as e:
    print(f"  ⚠ Failed to add the public text guard hook: {e}", file=sys.stderr)
    sys.exit(1)
PYTHON_SCRIPT
}

# Claude Code deletes session transcripts after 30 days unless told otherwise,
# and with them every conversation `--resume` could reopen. Keep them for a
# century; a value the user already set is theirs and stays.
configure_transcript_retention() {
    python3 - "${SETTINGS_JSON}" <<'PYTHON_SCRIPT'
import json
import sys

settings_file = sys.argv[1]
try:
    with open(settings_file) as f:
        data = json.load(f)
    if 'cleanupPeriodDays' in data:
        print(f"  ✓ Transcript retention already set ({data['cleanupPeriodDays']} days)")
        sys.exit(0)
    data['cleanupPeriodDays'] = 36500
    with open(settings_file, 'w') as f:
        json.dump(data, f, indent=2)
        f.write('\n')
    print("  ✓ Transcripts kept for 36500 days")
except Exception as e:
    print(f"  ⚠ Failed to set transcript retention: {e}", file=sys.stderr)
    sys.exit(1)
PYTHON_SCRIPT
}

# Commits and pull requests Claude writes name no claude.ai session link, as in
# the repo's settings; a value the user set stays. The stop-nudge hook now
# comes from the config-hooks plugin, so an older copy registered by hand in
# settings.json, which would run it twice, is removed.
configure_session_privacy() {
    python3 - "${SETTINGS_JSON}" <<'PYTHON_SCRIPT'
import json
import sys

settings_file = sys.argv[1]
try:
    with open(settings_file) as f:
        data = json.load(f)
    said = []
    attribution = data.setdefault('attribution', {})
    if 'sessionUrl' in attribution:
        said.append(f"  ✓ Session links already set (sessionUrl {str(attribution['sessionUrl']).lower()})")
    else:
        attribution['sessionUrl'] = False
        said.append("  ✓ Commits and pull requests name no session link")
    stop = data.get('hooks', {}).get('Stop', [])
    kept = []
    for group in stop:
        hooks = [h for h in group.get('hooks', []) if not str(h.get('command', '')).endswith('hooks/stop-nudge.sh')]
        if hooks:
            kept.append({**group, 'hooks': hooks})
    if kept != stop:
        if kept:
            data['hooks']['Stop'] = kept
        else:
            del data['hooks']['Stop']
        said.append("  ✓ Removed a hand-registered stop-nudge hook; the config-hooks plugin runs it")
    with open(settings_file, 'w') as f:
        json.dump(data, f, indent=2)
        f.write('\n')
    print('\n'.join(said))
except Exception as e:
    print(f"  ⚠ Failed to set session privacy: {e}", file=sys.stderr)
    sys.exit(1)
PYTHON_SCRIPT
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
import os
import sys

settings_file = sys.argv[1]
ref = os.environ.get('CLAUDE_DIR_REF', '~/.claude')

try:
    with open(settings_file) as f:
        data = json.load(f)

    data['fileSuggestion'] = {
        "type": "command",
        "command": f"{ref}/scripts/file-suggestion.sh"
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

# The Bash tool executes zsh whatever the login shell is, and zsh does not
# word-split unquoted parameters the way bash does, so a bash-shaped command
# collapses into one argument instead of erroring. Pinning the shell removes it.
#
# Unix only, deliberately: on Windows the tool always uses Git Bash and ignores
# this variable, so the exec shell is already bash and there is nothing to pin.
configure_bash_shell() {
    python3 - "${SETTINGS_JSON}" <<'PYTHON_SCRIPT'
import json
import os
import subprocess
import sys

settings_file = sys.argv[1]

# Apple freezes /bin/bash at 3.2 for licensing, so prefer a newer one if present.
CANDIDATES = (
    '/opt/homebrew/bin/bash',
    '/usr/local/bin/bash',
    '/usr/bin/bash',
    '/bin/bash',
)


def best_bash():
    best = None
    for path in CANDIDATES:
        if not os.access(path, os.X_OK):
            continue
        try:
            out = subprocess.run(
                [path, '-c', 'echo $BASH_VERSION'],
                capture_output=True, text=True, timeout=10,
            ).stdout.strip()
        except Exception:
            continue
        major = int(out.split('.')[0]) if out[:1].isdigit() else 0
        if best is None or major > best[1]:
            best = (path, major)
    return best[0] if best else None


try:
    shell = best_bash()
    if shell is None:
        print("  ⊘ No bash on this machine; leaving the exec shell as-is")
        sys.exit(0)

    with open(settings_file) as f:
        data = json.load(f)

    env = data.setdefault('env', {})
    if env.get('CLAUDE_CODE_SHELL') == shell:
        print(f"  ✓ Bash tool shell already pinned to {shell}")
        sys.exit(0)

    env['CLAUDE_CODE_SHELL'] = shell
    with open(settings_file, 'w') as f:
        json.dump(data, f, indent=2)

    print(f"  ✓ Bash tool shell pinned to {shell}")
    sys.exit(0)
except Exception as e:
    print(f"  ⚠ Failed to pin the Bash tool shell: {e}", file=sys.stderr)
    sys.exit(1)
PYTHON_SCRIPT
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

    # $USER is not guaranteed to be exported — Docker, cron, systemd units and
    # `sudo` without -E all reach here without it. `id -un` asks the system
    # instead of trusting the environment. Without this the lookups below query
    # an empty username, every one fails, and detection falls through to $SHELL:
    # silently re-introducing the exact bug this function exists to fix, while
    # still reporting success.
    local user="${USER:-}"
    [[ -z "${user}" ]] && user="$(id -un 2>/dev/null || true)"
    if [[ -z "${user}" ]]; then
        printf '%s\n' "${SHELL:-}"
        return
    fi

    # macOS: OpenDirectory, not /etc/passwd.
    if command -v dscl >/dev/null 2>&1; then
        found="$(dscl . -read "/Users/${user}" UserShell 2>/dev/null | awk '{print $2}')"
    fi

    # Linux / BSD: nsswitch-aware lookup, then the flat file.
    if [[ -z "${found}" ]] && command -v getent >/dev/null 2>&1; then
        found="$(getent passwd "${user}" 2>/dev/null | cut -d: -f7)"
    fi
    if [[ -z "${found}" && -r /etc/passwd ]]; then
        found="$(awk -F: -v u="${user}" '$1 == u { print $7 }' /etc/passwd 2>/dev/null | head -1)"
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
            _replace_contents "${tmp}" "${shell_profile}"

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
            _replace_contents "${tmp}" "${shell_profile}"
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
# A resumed session runs as the account it last ran as (claude-as --where),
# also when herdr resumes it after a restart, and keeps its own name in
# Remote Control (claude-as --rc-name). A subshell keeps the variables out of
# the caller's shell.
claude() (
  if [ -z "${CLAUDE_CONFIG_DIR:-}" ] && command -v claude-as >/dev/null 2>&1; then
    CLAUDE_CONFIG_DIR=$(claude-as --where "$@" 2>/dev/null) || {
      printf 'claude: claude-as --where failed; running as the default account\n' >&2
      CLAUDE_CONFIG_DIR=
    }
    if [ -n "${CLAUDE_CONFIG_DIR}" ]; then
      printf 'claude: as the session last ran, in %s\n' "${CLAUDE_CONFIG_DIR}" >&2
      export CLAUDE_CONFIG_DIR
    else
      unset CLAUDE_CONFIG_DIR
    fi
  fi
  mode=--allow-dangerously-skip-permissions
  case "${1:-}" in
    -a|--unsafe|--bypass|-adskp)
      shift
      mode=--dangerously-skip-permissions
      ;;
  esac
  if command -v claude-as >/dev/null 2>&1; then
    # In front: an option after a `--` or a prompt would not be read as one.
    rc_name=$(claude-as --rc-name "$@" 2>/dev/null) || rc_name=
    if [ -n "${rc_name}" ]; then
      set -- --remote-control "${rc_name}" "$@"
    fi
    if [ -z "${CLAUDE_REMOTE_CONTROL_SESSION_NAME_PREFIX:-}" ]; then
      host_alias=$(claude-as --host-alias 2>/dev/null) || host_alias=
      if [ -n "${host_alias}" ]; then
        export CLAUDE_REMOTE_CONTROL_SESSION_NAME_PREFIX="claude-${host_alias}"
      fi
    fi
  fi
  command claude "${mode}" "$@"
)

# No `local`: this block is written to ~/.profile for any shell that is not
# bash or zsh, and `local` is not in POSIX — it is a widely-implemented
# extension, not a guarantee. Expanding the parameter inline needs no variable,
# so nothing leaks into the caller's environment either.
clp() {
  case "${1:-}" in
    -a|--unsafe|--bypass|-adskp)
      shift
      claude-proxy --no-validate -m "${CLAUDE_PROXY_MODEL:-gpt-6.1-sol(high)}" -- --dangerously-skip-permissions "$@"
      ;;
    *)
      claude-proxy --no-validate -m "${CLAUDE_PROXY_MODEL:-gpt-6.1-sol(high)}" -- --allow-dangerously-skip-permissions "$@"
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

    # Creating ~/.bash_profile is not a neutral act. A bash login shell reads the
    # FIRST of ~/.bash_profile, ~/.bash_login, ~/.profile and stops — so on a
    # machine that has only ~/.profile (the Debian/Ubuntu default) this file
    # shadows it, and the user's exports silently stop loading. Carry ~/.profile
    # forward when we are the ones introducing the file.
    local carry=""
    if [[ ! -f "${profile}" && ! -f "${HOME}/.bash_login" && -f "${HOME}/.profile" ]]; then
        carry='[ -f "${HOME}/.profile" ] && . "${HOME}/.profile"'
    fi

    {
        printf '\n%s\n' "${marker}"
        [[ -n "${carry}" ]] && printf '%s\n' "${carry}"
        printf '%s\n' '[ -f "${HOME}/.bashrc" ] && . "${HOME}/.bashrc"'
    } >>"${profile}"

    echo "  ✓ ${profile} now sources ~/.bashrc (macOS terminals start login shells)"
    [[ -n "${carry}" ]] \
        && echo "    (and ~/.profile, which a new ~/.bash_profile would otherwise shadow)"
    return 0
}

# Write a managed fish file, unless the user owns it.
#
# The POSIX branch delimits its block with markers and refuses to rewrite when
# they are not intact. The fish branch had no equivalent: it wrote each function
# with `cat >`, so a hand-customised claude.fish was replaced without a word.
# That is the same silent-destruction failure the markers exist to prevent, and
# fish users are exactly the people likely to have customised these, since until
# recently setup.sh never installed them at all.
#
# Every file this function generates carries MANAGED_MARKER. Its presence means
# we wrote it and may regenerate it; its absence means someone else did.
MANAGED_MARKER="Managed by claude-code-config setup.sh"

_write_managed_fish() {
    local target="$1" label="$2"

    if [[ -f "${target}" ]] && ! grep -qF "${MANAGED_MARKER}" "${target}" 2>/dev/null; then
        local backup
        backup="${target}.bak.$(date +%s)"
        cp "${target}" "${backup}" 2>/dev/null || true
        cat >/dev/null # drain the heredoc we were given, so the caller still works
        echo "  ⚠ ${target} was not written by setup.sh — leaving it alone."
        echo "    Backup: ${backup}"
        echo "    Delete or rename it and re-run setup to install the managed ${label}."
        return 0
    fi

    cat >"${target}"
    echo "  ✓ ${label} → ${target}"
}

configure_fish_shell() {
    local bin_dir="$1"
    local fish_dir="${XDG_CONFIG_HOME:-${HOME}/.config}/fish"
    local functions_dir="${fish_dir}/functions"
    local confd_dir="${fish_dir}/conf.d"
    local path_file="${confd_dir}/00-claude-code-config-path.fish"

    mkdir -p "${functions_dir}" "${confd_dir}"

    # Single-quote the path for fish. Unquoted, a clone under a directory with a
    # space becomes two arguments, fish_add_path finds neither, and — because it
    # skips missing directories silently — the entry is dropped with no error.
    # In fish single quotes only \ and ' are special, so escaping those is enough.
    local fish_bin_dir="${bin_dir//\\/\\\\}"
    fish_bin_dir="${fish_bin_dir//\'/\\\'}"

    _write_managed_fish "${path_file}" "proxy launcher PATH" <<EOF
# claude-code-config: proxy launcher PATH
# Managed by claude-code-config setup.sh — regenerated on each run.
# fish_add_path is idempotent and silently skips missing directories.
fish_add_path -ga '${fish_bin_dir}'
EOF

    # The routing lives in its own function, so a hand-written claude.fish,
    # which setup leaves alone, can call it too.
    _write_managed_fish "${functions_dir}/__claude_as_home.fish" "resume routing function" <<'EOF'
function __claude_as_home --description 'The home a resumed session last ran in'
    # Managed by claude-code-config setup.sh.
    # Prints the home `claude-as --where` names for these claude arguments, or
    # nothing: a session not resumed, one that last ran in ~/.claude, or a
    # CLAUDE_CONFIG_DIR already set. A claude function routes with:
    #   set -l home (__claude_as_home $argv)
    #   test -n "$home"; and set -lx CLAUDE_CONFIG_DIR $home
    set -q CLAUDE_CONFIG_DIR; and return 0
    command -q claude-as; or return 0
    set -l home (command claude-as --where $argv 2>/dev/null)
    or begin
        printf 'claude: claude-as --where failed; running as the default account\n' >&2
        return 0
    end
    test -n "$home"; or return 0
    printf 'claude: as the session last ran, in %s\n' $home >&2
    printf '%s\n' $home
end
EOF

    _write_managed_fish "${functions_dir}/claude.fish" "claude function" <<'EOF'
function claude --description 'Claude Code with proxy launcher defaults'
    # Managed by claude-code-config setup.sh.
    # Defaults to --allow-dangerously-skip-permissions; opt in to
    # --dangerously-skip-permissions via -a / --unsafe / --bypass / -adskp.
    # A resumed session runs as the account it last ran as (__claude_as_home),
    # also when herdr resumes it after a restart, and keeps its own name in
    # Remote Control (claude-as --rc-name).

    set -l home (__claude_as_home $argv)
    # Outside any block: a variable set in one ends with it.
    test -n "$home"; and set -lx CLAUDE_CONFIG_DIR $home

    set -l mode --allow-dangerously-skip-permissions
    set -l rest $argv
    if contains -- "$argv[1]" -a --unsafe --bypass -adskp
        set mode --dangerously-skip-permissions
        set -e rest[1]
    end

    set -l rc_name
    set -l host_alias
    if command -q claude-as
        set rc_name (command claude-as --rc-name $rest 2>/dev/null)
        set host_alias (command claude-as --host-alias 2>/dev/null)
    end
    # In front: an option after a `--` or a prompt would not be read as one.
    test -n "$rc_name"; and set rest --remote-control $rc_name $rest
    # Outside any block, as CLAUDE_CONFIG_DIR above.
    test -z "$CLAUDE_REMOTE_CONTROL_SESSION_NAME_PREFIX"; and test -n "$host_alias"
    and set -lx CLAUDE_REMOTE_CONTROL_SESSION_NAME_PREFIX claude-$host_alias
    command claude $mode $rest
end
EOF

    _write_managed_fish "${functions_dir}/clp.fish" "clp function" <<'EOF'
function clp --description 'Claude proxy with model'
    # Managed by claude-code-config setup.sh.

    set -l model 'gpt-6.1-sol(high)'
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

    local claude_fn="${functions_dir}/claude.fish"
    if [[ -f ${claude_fn} ]] && ! grep -qF "${MANAGED_MARKER}" "${claude_fn}" \
        && ! grep -qF '__claude_as_home' "${claude_fn}"; then
        echo "  ⚠ ${claude_fn} does not route a resume to its account:"
        echo "    \`claude --resume <id>\`, and herdr restoring a pane, run as ~/.claude"
        echo "    whatever account the session last ran as. Add at the top of the"
        echo "    function, outside any if or switch:"
        echo "      set -l home (__claude_as_home \$argv)"
        echo "      test -n \"\$home\"; and set -lx CLAUDE_CONFIG_DIR \$home"
    fi

    echo ""
    echo "  Open a new terminal (or 'exec fish'), then:"
    echo "    claude --help"
    echo "    claude -a"
    echo "    clp -a"
    echo "    claude-proxy -p antigravity --models"
}

# The statusline redraws on a timer as well as on events, so an idle session
# keeps its countdowns moving and picks up usage other sessions spent. A
# statusline someone else configured is left as it is.
configure_statusline() {
    python3 - "${SETTINGS_JSON}" <<'PYTHON_SCRIPT'
import json
import os
import sys

settings_file = sys.argv[1]
ref = os.environ.get('CLAUDE_DIR_REF', '~/.claude')
REFRESH = 60

try:
    with open(settings_file) as f:
        data = json.load(f)

    line = data.get('statusLine')
    if line is None:
        data['statusLine'] = {
            "type": "command",
            "command": f"{ref}/scripts/statusline.sh",
            "padding": 0,
            "refreshInterval": REFRESH,
        }
        message = "  ✓ Statusline configured"
    elif (isinstance(line, dict) and 'refreshInterval' not in line
          and str(line.get('command', '')).endswith('/scripts/statusline.sh')):
        line['refreshInterval'] = REFRESH
        message = f"  ✓ Statusline refreshes every {REFRESH}s"
    else:
        print("  ✓ Statusline already configured")
        sys.exit(0)

    with open(settings_file, 'w') as f:
        json.dump(data, f, indent=2)
    print(message)
except Exception as e:
    print(f"  ⚠ Failed to configure the statusline: {e}", file=sys.stderr)
    sys.exit(1)
PYTHON_SCRIPT
}

remove_legacy_claude_sync_hooks() {
    # ~/.claude contains live, mutable session journals. Bidirectional file
    # sync is not a safe merge protocol for that data, so setup permanently
    # removes hook entries installed by older releases. Declarative config is
    # still distributed through Git; cross-device sessions use Remote Control.
    python3 - "${SETTINGS_JSON}" <<'PYTHON_SCRIPT'
import json
import os
import sys

settings_file = sys.argv[1]
ref = os.environ.get('CLAUDE_DIR_REF', '~/.claude')

try:
    with open(settings_file) as f:
        data = json.load(f)

    hooks = data.get('hooks', {})
    changed = False

    for event, script in (
        ('SessionStart', 'cc-sync-pull.sh'),
        ('SessionEnd', 'cc-sync-push.sh'),
    ):
        targets = {f'~/.claude/hooks/{script}', f'{ref}/hooks/{script}'}
        entries = hooks.get(event, [])
        kept = []
        for entry in entries:
            original = entry.get('hooks', [])
            sub = [h for h in original if h.get('command') not in targets]
            if len(sub) != len(original):
                changed = True
            if sub:
                entry['hooks'] = sub
                kept.append(entry)
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
        print("  ✓ Retired claude-sync session hooks removed")
    else:
        print("  ⊘ Retired claude-sync session hooks not present")
    sys.exit(0)
except Exception as e:
    print(f"  ⚠ Failed to remove retired claude-sync hooks: {e}", file=sys.stderr)
    sys.exit(1)
PYTHON_SCRIPT
}
