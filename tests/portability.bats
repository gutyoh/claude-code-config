#!/usr/bin/env bats
# portability.bats -- repo-wide guards against machine-specific assumptions.
#
# This repo is installed on other people's machines, so nothing shipped may
# depend on one developer's paths, shell, package manager, or OS. These are
# static guards: they read the tree rather than exercising behaviour, so they
# stay fast and run in the `unit` lane.

bats_require_minimum_version 1.5.0

setup() {
    source "$BATS_TEST_DIRNAME/helpers.bash"
    REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
    export REPO_ROOT
}

# Files we ship and therefore must keep portable. Docs prose may legitimately
# name absolute paths as examples, so only executable/config content is scanned.
shipped_scripts() {
    git -C "$REPO_ROOT" ls-files -z \
        -- '*.sh' 'bin/*' '.claude/hooks/*' '*.bats' '*.fish' 2>/dev/null |
        tr '\0' '\n' | grep -v '^docs/' || true
}

# --- Hardcoded home directories -------------------------------------------

# bats test_tags=unit,portability
@test "no shipped script hardcodes a user home directory" {
    local hits
    hits="$(cd "$REPO_ROOT" && shipped_scripts | while read -r f; do
        [[ -n "$f" ]] || continue
        grep -Hn -E '/(Users|home)/[a-z][a-z0-9_-]*' "$f" 2>/dev/null |
            grep -v -E '(<user>|\$\{?USER|/home/linuxbrew|example|placeholder)' || true
    done)"
    [ -z "$hits" ] || {
        echo "Hardcoded home directories found:"
        echo "$hits"
        false
    }
}

# --- Hardcoded package-manager prefixes ------------------------------------

# bats test_tags=unit,portability
@test "no shipped script assumes a single brew prefix without probing" {
    # /opt/homebrew is Apple-Silicon-only; /usr/local is Intel and Linux.
    # Naming it inside a candidate list that also offers the alternatives is
    # correct — that is how you find the right prefix. Naming it alone is not.
    local hits
    hits="$(cd "$REPO_ROOT" && shipped_scripts | while read -r f; do
        [[ -n "$f" ]] || continue
        grep -q '/opt/homebrew' "$f" 2>/dev/null || continue
        grep -qE '/usr/local|linuxbrew' "$f" 2>/dev/null ||
            echo "$f: /opt/homebrew with no non-Apple-Silicon alternative"
    done)"
    [ -z "$hits" ] || {
        echo "$hits"
        false
    }
}

# --- Ghostty presets --------------------------------------------------------

# bats test_tags=unit,portability
@test "ghostty presets ship no active absolute command= path" {
    local hits
    hits="$(grep -rn '^command = ' "$REPO_ROOT/docs/ghostty/" 2>/dev/null || true)"
    [ -z "$hits" ] || {
        echo "Active absolute command= in a shipped preset:"
        echo "$hits"
        false
    }
}

# --- XDG Base Directory -----------------------------------------------------

# bats test_tags=unit,portability
@test "config paths honour XDG_CONFIG_HOME instead of assuming ~/.config" {
    local hits
    hits="$(cd "$REPO_ROOT" && shipped_scripts | while read -r f; do
        [[ -n "$f" ]] || continue
        grep -Hn -E '\$\{?HOME\}?/\.config' "$f" 2>/dev/null |
            grep -v 'XDG_CONFIG_HOME' || true
    done)"
    [ -z "$hits" ] || {
        echo "\$HOME/.config used without an XDG_CONFIG_HOME fallback:"
        echo "$hits"
        false
    }
}

# bats test_tags=unit,portability
@test "opencode config dir follows XDG_CONFIG_HOME when set" {
    XDG_CONFIG_HOME="$BATS_TEST_TMPDIR/xdg" \
        HOME="$BATS_TEST_TMPDIR/home" \
        run bash -c "source '$REPO_ROOT/lib/setup/opencode.sh'; echo \"\$OPENCODE_CONFIG_DIR\""
    [ "$status" -eq 0 ]
    [[ "$output" == "$BATS_TEST_TMPDIR/xdg/opencode" ]]
}

# bats test_tags=unit,portability
@test "opencode config dir falls back to ~/.config when XDG unset" {
    run env -u XDG_CONFIG_HOME HOME="$BATS_TEST_TMPDIR/home" \
        bash -c "source '$REPO_ROOT/lib/setup/opencode.sh'; echo \"\$OPENCODE_CONFIG_DIR\""
    [ "$status" -eq 0 ]
    [[ "$output" == "$BATS_TEST_TMPDIR/home/.config/opencode" ]]
}

# --- Non-portable sed -------------------------------------------------------

# bats test_tags=unit,portability
@test "no shipped script uses [^\\\\n] in a sed expression" {
    # `[^\n]` is not portable: BSD sed reads it as "not backslash and not the
    # letter n", GNU sed as "not newline". Code relying on it behaves
    # differently on macOS and Linux, usually silently.
    local hits
    hits="$(cd "$REPO_ROOT" && shipped_scripts | while read -r f; do
        [[ -n "$f" ]] || continue
        # Strip comment lines first: this guard and its regression tests both
        # have to name the bad pattern in prose to explain it.
        grep -Hn 'sed' "$f" 2>/dev/null |
            grep -v -E '^[^:]+:[0-9]+:[[:space:]]*#' |
            grep '\[^\\n\]' || true
    done)"
    [ -z "$hits" ] || {
        echo "Non-portable sed bracket expression:"
        echo "$hits"
        false
    }
}

# --- GNU-only tool flags ----------------------------------------------------

# bats test_tags=unit,portability
@test "no shipped script uses GNU-only flags without a BSD path" {
    # `stat -c` and `date -d` are GNU-only. Two shapes make them safe: an
    # explicit platform branch, or a `stat -f … || stat -c …` fallback pair.
    # Anything else breaks on macOS.
    local hits
    hits="$(cd "$REPO_ROOT" && shipped_scripts | while read -r f; do
        [[ -n "$f" ]] || continue
        grep -qE 'stat -c|date -d ' "$f" 2>/dev/null || continue
        grep -qE 'Darwin|darwin|macos|uname|OSTYPE|PLATFORM' "$f" 2>/dev/null && continue
        grep -qE 'stat -f|date -r|date -j' "$f" 2>/dev/null && continue
        echo "$f: GNU-only flag with neither platform branch nor BSD fallback"
    done)"
    [ -z "$hits" ] || {
        echo "$hits"
        false
    }
}

# --- Shebangs ---------------------------------------------------------------

# bats test_tags=unit,portability
@test "every shipped script uses env-based shebang" {
    local hits
    hits="$(cd "$REPO_ROOT" && shipped_scripts | while read -r f; do
        [[ -n "$f" ]] || continue
        head -1 "$f" 2>/dev/null | grep -q '^#!' || continue
        head -1 "$f" | grep -qE '^#!/usr/bin/env ' || echo "$f: $(head -1 "$f")"
    done)"
    [ -z "$hits" ] || {
        echo "Non-portable shebang (hardcodes an interpreter path):"
        echo "$hits"
        false
    }
}

# --- bash version guard -----------------------------------------------------

# bats test_tags=unit,portability
@test "setup.sh guards against bash older than 4.3" {
    grep -q 'BASH_VERSINFO' "$REPO_ROOT/setup.sh"
}

# bats test_tags=integration,portability
@test "setup.sh --help succeeds under stock macOS bash 3.2" {
    [ -x /bin/bash ] || skip "no /bin/bash on this platform"
    local ver
    ver="$(/bin/bash -c 'echo ${BASH_VERSINFO[0]}.${BASH_VERSINFO[1]}')"
    [[ "$ver" == "3.2" ]] || skip "/bin/bash is $ver, not the 3.2 we want to guard against"

    run /bin/bash "$REPO_ROOT/setup.sh" --help
    [ "$status" -eq 0 ]
    [[ "$output" == *"Usage: setup.sh"* ]]
}

# bats test_tags=integration,portability
@test "setup.sh fails with actionable message when no modern bash exists" {
    [ -x /bin/bash ] || skip "no /bin/bash on this platform"
    local ver
    ver="$(/bin/bash -c 'echo ${BASH_VERSINFO[0]}.${BASH_VERSINFO[1]}')"
    [[ "$ver" == "3.2" ]] || skip "/bin/bash is $ver, not the 3.2 we want to guard against"

    # CLAUDE_CONFIG_BASH_REEXEC set = "we already tried to upgrade", so the
    # guard must stop rather than loop.
    run env CLAUDE_CONFIG_BASH_REEXEC=1 /bin/bash "$REPO_ROOT/setup.sh" --help
    [ "$status" -eq 1 ]
    [[ "$output" == *"bash >= 4.3"* ]]
    [[ "$output" == *"brew install bash"* ]]
}
